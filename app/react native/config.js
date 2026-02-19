/**
 * App Configuration
 * 
 * Centralized configuration for the Flood Detection app.
 * Update these values to customize the app behavior.
 */

export const config = {
    // ============================================
    // API CONFIGURATION
    // ============================================

    // Your AI model API endpoint
    // Replace this with your actual API URL when ready
    apiEndpoint: 'http://your-api-endpoint.com/api',

    // API timeout in milliseconds
    apiTimeout: 30000,

    // Use mock data for testing (set to false when using real API)
    useMockData: true,

    // ============================================
    // APP SETTINGS
    // ============================================

    // Maximum number of detections to store in history
    maxHistoryItems: 50,

    // Image quality for camera/gallery (0.0 - 1.0)
    imageQuality: 0.8,

    // Image aspect ratio for cropping [width, height]
    imageAspectRatio: [4, 3],

    // ============================================
    // FEATURE FLAGS
    // ============================================

    // Enable/disable features
    features: {
        // Save detection history locally
        saveHistory: true,

        // Show confidence percentage
        showConfidence: true,

        // Show water level indicator
        showWaterLevel: true,

        // Show severity badge
        showSeverity: true,

        // Show recommendations
        showRecommendations: true,

        // Enable retry on failure
        enableRetry: true,
    },

    // ============================================
    // UI CUSTOMIZATION
    // ============================================

    ui: {
        // App name displayed in the UI
        appName: 'Flood Detection AI',

        // Tagline/subtitle
        tagline: 'AI-powered flood analysis from images',

        // Animation duration in milliseconds
        animationDuration: 600,

        // Enable animations
        enableAnimations: true,
    },

    // ============================================
    // MESSAGES
    // ============================================

    messages: {
        // Loading message
        analyzing: 'Analyzing image...',
        analyzingSubtext: 'Our AI is processing your image',

        // Error messages
        noImage: 'Please select or capture an image first.',
        analysisError: 'An unexpected error occurred. Please try again.',

        // Permission messages
        cameraPermission: 'Camera permission is required to take photos.',
        galleryPermission: 'Gallery permission is required to select photos.',
    },

    // ============================================
    // THRESHOLDS
    // ============================================

    thresholds: {
        // Confidence threshold for showing warnings (0-100)
        lowConfidenceWarning: 50,

        // Water level thresholds for severity classification
        waterLevel: {
            low: 30,      // Below 30% = Low
            medium: 60,   // 30-60% = Medium
            high: 60,     // Above 60% = High
        },
    },
};

// ============================================
// HELPER FUNCTIONS
// ============================================

/**
 * Get the API endpoint URL
 */
export const getApiEndpoint = () => {
    return config.apiEndpoint;
};

/**
 * Check if mock data should be used
 */
export const shouldUseMockData = () => {
    return config.useMockData;
};

/**
 * Check if a feature is enabled
 */
export const isFeatureEnabled = (featureName) => {
    return config.features[featureName] ?? false;
};

/**
 * Get a UI message
 */
export const getMessage = (messageKey) => {
    return config.messages[messageKey] ?? '';
};

// ============================================
// ENVIRONMENT-SPECIFIC CONFIGURATION
// ============================================

/**
 * You can also use different configs for different environments
 * Uncomment and modify as needed
 */

// Development configuration
export const devConfig = {
    ...config,
    apiEndpoint: 'http://localhost:3000/api',
    useMockData: true,
};

// Production configuration
export const prodConfig = {
    ...config,
    apiEndpoint: 'https://api.yourproduction.com/api',
    useMockData: false,
};

// Staging configuration
export const stagingConfig = {
    ...config,
    apiEndpoint: 'https://staging-api.yourapp.com/api',
    useMockData: false,
};

/**
 * To use environment-specific configs:
 * 
 * 1. Install expo-constants:
 *    npx expo install expo-constants
 * 
 * 2. Create app.config.js with:
 *    export default {
 *      expo: {
 *        extra: {
 *          environment: process.env.APP_ENV || 'development',
 *        },
 *      },
 *    };
 * 
 * 3. Use in your code:
 *    import Constants from 'expo-constants';
 *    const environment = Constants.expoConfig.extra.environment;
 *    const config = environment === 'production' ? prodConfig : devConfig;
 */

export default config;
