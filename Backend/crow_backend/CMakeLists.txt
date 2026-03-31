cmake_minimum_required(VERSION 3.15)
project(FloodPredictionServer VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ─── Dependencies via FetchContent ───────────────
include(FetchContent)

# Crow (header-only web framework)
FetchContent_Declare(
    crow
    GIT_REPOSITORY https://github.com/CrowCpp/Crow.git
    GIT_TAG        v1.2.0
)
FetchContent_MakeAvailable(crow)

# nlohmann/json (header-only JSON library)
FetchContent_Declare(
    json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
)
FetchContent_MakeAvailable(json)

# cpr (C++ Requests - HTTP client)
FetchContent_Declare(
    cpr
    GIT_REPOSITORY https://github.com/libcpr/cpr.git
    GIT_TAG        1.10.5
)
set(CPR_USE_SYSTEM_CURL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(cpr)

# ─── Include directories ────────────────────────
include_directories(${CMAKE_SOURCE_DIR}/include)

# ─── Source files ────────────────────────────────
set(SOURCES
    src/main.cpp
    src/weather_service.cpp
    src/model_service.cpp
    src/gemini_service.cpp
)

# ─── Build executable ───────────────────────────
add_executable(flood_prediction_server ${SOURCES})

target_link_libraries(flood_prediction_server
    PRIVATE
        Crow::Crow
        nlohmann_json::nlohmann_json
        cpr::cpr
)

# ─── Platform-specific threading ────────────────
find_package(Threads REQUIRED)
target_link_libraries(flood_prediction_server PRIVATE Threads::Threads)

# ─── Copy models directory to build ─────────────
add_custom_command(
    TARGET flood_prediction_server POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
        $<TARGET_FILE_DIR:flood_prediction_server>/models
    COMMENT "Creating models directory in build output"
)

# ─── Installation ───────────────────────────────
install(TARGETS flood_prediction_server
    RUNTIME DESTINATION bin
)
