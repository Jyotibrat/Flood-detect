import React, { useState, useEffect } from 'react';
import {
    View,
    Text,
    StyleSheet,
    ScrollView,
    ActivityIndicator,
    TouchableOpacity,
    Alert,
    RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as Location from 'expo-location';
import { LinearGradient } from 'expo-linear-gradient';
import CustomButton from '../components/CustomButton';
import { colors, spacing, borderRadius, shadows, typography } from '../styles/theme';
import { getCurrentWeather, getHistoricalWeather, mockPredictFlood } from '../services/api';

const HomeScreen = ({ navigation }) => {
    const [location, setLocation] = useState(null);
    const [currentWeather, setCurrentWeather] = useState(null);
    const [historicalWeather, setHistoricalWeather] = useState(null);
    const [loading, setLoading] = useState(false);
    const [refreshing, setRefreshing] = useState(false);
    const [error, setError] = useState(null);

    useEffect(() => {
        requestLocationPermission();
    }, []);

    const requestLocationPermission = async () => {
        try {
            const { status } = await Location.requestForegroundPermissionsAsync();
            if (status !== 'granted') {
                Alert.alert(
                    'Permission Required',
                    'Location permission is required to fetch weather data for flood prediction.',
                    [{ text: 'OK' }]
                );
                return;
            }
            fetchWeatherData();
        } catch (error) {
            console.error('Error requesting location permission:', error);
            setError('Failed to get location permission');
        }
    };

    const fetchWeatherData = async () => {
        setLoading(true);
        setError(null);

        try {
            // Get current location
            const locationData = await Location.getCurrentPositionAsync({
                accuracy: Location.Accuracy.Balanced,
            });

            setLocation(locationData.coords);

            // Fetch current weather
            const currentWeatherResponse = await getCurrentWeather(
                locationData.coords.latitude,
                locationData.coords.longitude
            );

            if (!currentWeatherResponse.success) {
                throw new Error(currentWeatherResponse.error);
            }

            setCurrentWeather(currentWeatherResponse.data);

            // Fetch historical weather (yesterday)
            const historicalWeatherResponse = await getHistoricalWeather(
                locationData.coords.latitude,
                locationData.coords.longitude
            );

            if (!historicalWeatherResponse.success) {
                throw new Error(historicalWeatherResponse.error);
            }

            setHistoricalWeather(historicalWeatherResponse.data);

        } catch (err) {
            console.error('Error fetching weather data:', err);
            setError(err.message || 'Failed to fetch weather data');

            // Use mock data for demo
            setCurrentWeather({
                name: 'Your Location',
                main: { temp: 28, humidity: 75, pressure: 1013 },
                weather: [{ description: 'partly cloudy', main: 'Clouds' }],
                rain: { '1h': 5 },
                wind: { speed: 3.5 },
                clouds: { all: 60 },
                coord: { lat: 0, lon: 0 },
            });

            setHistoricalWeather({
                current: { temp: 27, humidity: 70, pressure: 1012, rain: { '1h': 3 }, wind_speed: 3, clouds: 55 },
            });
        } finally {
            setLoading(false);
            setRefreshing(false);
        }
    };

    const handleAnalyze = async () => {
        if (!currentWeather || !historicalWeather) {
            Alert.alert('No Data', 'Please fetch weather data first.');
            return;
        }

        navigation.navigate('Result', {
            currentWeather,
            historicalWeather,
        });
    };

    const onRefresh = () => {
        setRefreshing(true);
        fetchWeatherData();
    };

    const getWeatherIcon = (condition) => {
        const icons = {
            Clear: '☀️',
            Clouds: '☁️',
            Rain: '🌧️',
            Drizzle: '🌦️',
            Thunderstorm: '⛈️',
            Snow: '❄️',
            Mist: '🌫️',
            Fog: '🌫️',
        };
        return icons[condition] || '🌤️';
    };

    return (
        <SafeAreaView style={styles.container} edges={['top']}>
            <LinearGradient
                colors={[colors.background, '#1a1f3a']}
                style={styles.gradient}
            >
                <ScrollView
                    contentContainerStyle={styles.scrollContent}
                    showsVerticalScrollIndicator={false}
                    refreshControl={
                        <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.primary} />
                    }
                >
                    {/* Header */}
                    <View style={styles.header}>
                        <Text style={styles.title}>🌊 Flood Prediction</Text>
                        <Text style={styles.subtitle}>
                            AI-powered flood risk analysis based on weather data
                        </Text>
                    </View>

                    {/* Loading State */}
                    {loading && !currentWeather && (
                        <View style={styles.loadingContainer}>
                            <ActivityIndicator size="large" color={colors.primary} />
                            <Text style={styles.loadingText}>Fetching weather data...</Text>
                        </View>
                    )}

                    {/* Error State */}
                    {error && !currentWeather && (
                        <View style={styles.errorCard}>
                            <Text style={styles.errorIcon}>⚠️</Text>
                            <Text style={styles.errorText}>{error}</Text>
                            <CustomButton
                                title="Retry"
                                icon="🔄"
                                onPress={fetchWeatherData}
                                variant="primary"
                                style={styles.retryButton}
                            />
                        </View>
                    )}

                    {/* Weather Data Display */}
                    {currentWeather && (
                        <>
                            {/* Current Weather Card */}
                            <View style={styles.weatherCard}>
                                <View style={styles.cardHeader}>
                                    <Text style={styles.cardIcon}>🌡️</Text>
                                    <Text style={styles.cardTitle}>Current Weather</Text>
                                </View>

                                <View style={styles.weatherMain}>
                                    <Text style={styles.weatherIcon}>
                                        {getWeatherIcon(currentWeather.weather?.[0]?.main)}
                                    </Text>
                                    <View style={styles.weatherInfo}>
                                        <Text style={styles.temperature}>{Math.round(currentWeather.main.temp)}°C</Text>
                                        <Text style={styles.weatherDescription}>
                                            {currentWeather.weather?.[0]?.description || 'N/A'}
                                        </Text>
                                        <Text style={styles.locationText}>📍 {currentWeather.name || 'Your Location'}</Text>
                                    </View>
                                </View>

                                <View style={styles.weatherDetails}>
                                    <View style={styles.detailItem}>
                                        <Text style={styles.detailLabel}>💧 Humidity</Text>
                                        <Text style={styles.detailValue}>{currentWeather.main.humidity}%</Text>
                                    </View>
                                    <View style={styles.detailItem}>
                                        <Text style={styles.detailLabel}>🌧️ Rainfall</Text>
                                        <Text style={styles.detailValue}>{currentWeather.rain?.['1h'] || 0} mm</Text>
                                    </View>
                                    <View style={styles.detailItem}>
                                        <Text style={styles.detailLabel}>💨 Wind</Text>
                                        <Text style={styles.detailValue}>{currentWeather.wind?.speed || 0} m/s</Text>
                                    </View>
                                    <View style={styles.detailItem}>
                                        <Text style={styles.detailLabel}>🔽 Pressure</Text>
                                        <Text style={styles.detailValue}>{currentWeather.main.pressure} hPa</Text>
                                    </View>
                                </View>
                            </View>

                            {/* Yesterday's Weather Card */}
                            {historicalWeather && (
                                <View style={styles.weatherCard}>
                                    <View style={styles.cardHeader}>
                                        <Text style={styles.cardIcon}>📅</Text>
                                        <Text style={styles.cardTitle}>Yesterday's Weather</Text>
                                    </View>

                                    <View style={styles.weatherDetails}>
                                        <View style={styles.detailItem}>
                                            <Text style={styles.detailLabel}>🌡️ Temp</Text>
                                            <Text style={styles.detailValue}>
                                                {Math.round(historicalWeather.current?.temp || 0)}°C
                                            </Text>
                                        </View>
                                        <View style={styles.detailItem}>
                                            <Text style={styles.detailLabel}>💧 Humidity</Text>
                                            <Text style={styles.detailValue}>
                                                {historicalWeather.current?.humidity || 0}%
                                            </Text>
                                        </View>
                                        <View style={styles.detailItem}>
                                            <Text style={styles.detailLabel}>🌧️ Rainfall</Text>
                                            <Text style={styles.detailValue}>
                                                {historicalWeather.current?.rain?.['1h'] || 0} mm
                                            </Text>
                                        </View>
                                        <View style={styles.detailItem}>
                                            <Text style={styles.detailLabel}>💨 Wind</Text>
                                            <Text style={styles.detailValue}>
                                                {historicalWeather.current?.wind_speed || 0} m/s
                                            </Text>
                                        </View>
                                    </View>
                                </View>
                            )}

                            {/* Analyze Button */}
                            <CustomButton
                                title="Analyze Flood Risk"
                                icon="🔍"
                                onPress={handleAnalyze}
                                variant="primary"
                                style={styles.analyzeButton}
                            />
                        </>
                    )}

                    {/* Info Cards */}
                    <View style={styles.infoContainer}>
                        <View style={styles.infoCard}>
                            <Text style={styles.infoIcon}>🤖</Text>
                            <Text style={styles.infoTitle}>AI-Powered</Text>
                            <Text style={styles.infoText}>
                                Advanced machine learning for accurate predictions
                            </Text>
                        </View>

                        <View style={styles.infoCard}>
                            <Text style={styles.infoIcon}>🌦️</Text>
                            <Text style={styles.infoTitle}>Real-Time Data</Text>
                            <Text style={styles.infoText}>
                                Live weather data from reliable sources
                            </Text>
                        </View>

                        <View style={styles.infoCard}>
                            <Text style={styles.infoIcon}>📊</Text>
                            <Text style={styles.infoTitle}>Historical Analysis</Text>
                            <Text style={styles.infoText}>
                                Compares current and past weather patterns
                            </Text>
                        </View>
                    </View>
                </ScrollView>
            </LinearGradient>
        </SafeAreaView>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: colors.background,
    },
    gradient: {
        flex: 1,
    },
    scrollContent: {
        padding: spacing.lg,
        paddingBottom: spacing.xxl,
    },
    header: {
        marginBottom: spacing.xl,
        alignItems: 'center',
    },
    title: {
        ...typography.h1,
        color: colors.text,
        marginBottom: spacing.sm,
        textAlign: 'center',
    },
    subtitle: {
        ...typography.body,
        color: colors.textSecondary,
        textAlign: 'center',
    },
    loadingContainer: {
        padding: spacing.xxl,
        alignItems: 'center',
    },
    loadingText: {
        ...typography.body,
        color: colors.textSecondary,
        marginTop: spacing.md,
    },
    errorCard: {
        backgroundColor: colors.surface,
        padding: spacing.xl,
        borderRadius: borderRadius.lg,
        alignItems: 'center',
        marginBottom: spacing.lg,
        ...shadows.md,
    },
    errorIcon: {
        fontSize: 48,
        marginBottom: spacing.md,
    },
    errorText: {
        ...typography.body,
        color: colors.textSecondary,
        textAlign: 'center',
        marginBottom: spacing.lg,
    },
    retryButton: {
        width: '100%',
    },
    weatherCard: {
        backgroundColor: colors.surface,
        padding: spacing.lg,
        borderRadius: borderRadius.lg,
        marginBottom: spacing.lg,
        ...shadows.md,
    },
    cardHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: spacing.md,
        gap: spacing.sm,
    },
    cardIcon: {
        fontSize: 24,
    },
    cardTitle: {
        ...typography.h3,
        color: colors.text,
    },
    weatherMain: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: spacing.lg,
        gap: spacing.lg,
    },
    weatherIcon: {
        fontSize: 64,
    },
    weatherInfo: {
        flex: 1,
    },
    temperature: {
        ...typography.h1,
        color: colors.primary,
        fontSize: 40,
    },
    weatherDescription: {
        ...typography.body,
        color: colors.textSecondary,
        textTransform: 'capitalize',
        marginBottom: spacing.xs,
    },
    locationText: {
        ...typography.caption,
        color: colors.textSecondary,
    },
    weatherDetails: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: spacing.md,
    },
    detailItem: {
        flex: 1,
        minWidth: '45%',
        backgroundColor: colors.surfaceLight,
        padding: spacing.md,
        borderRadius: borderRadius.sm,
    },
    detailLabel: {
        ...typography.caption,
        color: colors.textSecondary,
        marginBottom: spacing.xs,
    },
    detailValue: {
        ...typography.body,
        color: colors.text,
        fontWeight: '600',
    },
    analyzeButton: {
        width: '100%',
        marginBottom: spacing.lg,
    },
    infoContainer: {
        gap: spacing.md,
    },
    infoCard: {
        backgroundColor: colors.surface,
        padding: spacing.lg,
        borderRadius: borderRadius.md,
        borderLeftWidth: 4,
        borderLeftColor: colors.primary,
        ...shadows.sm,
    },
    infoIcon: {
        fontSize: 32,
        marginBottom: spacing.sm,
    },
    infoTitle: {
        ...typography.h3,
        color: colors.text,
        marginBottom: spacing.xs,
    },
    infoText: {
        ...typography.caption,
        color: colors.textSecondary,
    },
});

export default HomeScreen;
