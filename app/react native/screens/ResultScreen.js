import React, { useState, useEffect } from 'react';
import {
    View,
    Text,
    StyleSheet,
    ScrollView,
    ActivityIndicator,
    Animated,
    TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import CustomButton from '../components/CustomButton';
import { mockPredictFlood } from '../services/api';
import { colors, spacing, borderRadius, shadows, typography } from '../styles/theme';

const ResultScreen = ({ route, navigation }) => {
    const { currentWeather, historicalWeather } = route.params;
    const [loading, setLoading] = useState(true);
    const [result, setResult] = useState(null);
    const [error, setError] = useState(null);
    const [fadeAnim] = useState(new Animated.Value(0));
    const [slideAnim] = useState(new Animated.Value(50));

    useEffect(() => {
        analyzePrediction();
    }, []);

    const analyzePrediction = async () => {
        setLoading(true);
        setError(null);

        try {
            // Use mockPredictFlood for now - replace with predictFlood when API is ready
            const response = await mockPredictFlood(currentWeather, historicalWeather);

            if (response.success) {
                setResult(response.data);

                // Animate results in
                Animated.parallel([
                    Animated.timing(fadeAnim, {
                        toValue: 1,
                        duration: 600,
                        useNativeDriver: true,
                    }),
                    Animated.timing(slideAnim, {
                        toValue: 0,
                        duration: 600,
                        useNativeDriver: true,
                    }),
                ]).start();
            } else {
                setError(response.error);
            }
        } catch (err) {
            setError('An unexpected error occurred. Please try again.');
            console.error('Prediction error:', err);
        } finally {
            setLoading(false);
        }
    };

    const handleRetry = () => {
        analyzePrediction();
    };

    const handleNewAnalysis = () => {
        navigation.goBack();
    };

    const getSeverityColor = (severity) => {
        switch (severity?.toLowerCase()) {
            case 'high':
                return colors.danger;
            case 'medium':
                return colors.warning;
            case 'low':
                return colors.secondary;
            default:
                return colors.textSecondary;
        }
    };

    const getRiskIcon = (isRisk) => {
        return isRisk ? '⚠️' : '✅';
    };

    if (loading) {
        return (
            <SafeAreaView style={styles.container} edges={['top']}>
                <LinearGradient
                    colors={[colors.background, '#1a1f3a']}
                    style={styles.gradient}
                >
                    <View style={styles.loadingContainer}>
                        <ActivityIndicator size="large" color={colors.primary} />
                        <Text style={styles.loadingText}>Analyzing weather patterns...</Text>
                        <Text style={styles.loadingSubtext}>
                            Our AI is processing the data
                        </Text>
                    </View>
                </LinearGradient>
            </SafeAreaView>
        );
    }

    if (error) {
        return (
            <SafeAreaView style={styles.container} edges={['top']}>
                <LinearGradient
                    colors={[colors.background, '#1a1f3a']}
                    style={styles.gradient}
                >
                    <View style={styles.errorContainer}>
                        <Text style={styles.errorIcon}>❌</Text>
                        <Text style={styles.errorTitle}>Analysis Failed</Text>
                        <Text style={styles.errorText}>{error}</Text>
                        <View style={styles.errorButtons}>
                            <CustomButton
                                title="Retry"
                                icon="🔄"
                                onPress={handleRetry}
                                variant="primary"
                                style={styles.errorButton}
                            />
                            <CustomButton
                                title="Go Back"
                                icon="←"
                                onPress={handleNewAnalysis}
                                variant="outline"
                                style={styles.errorButton}
                            />
                        </View>
                    </View>
                </LinearGradient>
            </SafeAreaView>
        );
    }

    return (
        <SafeAreaView style={styles.container} edges={['top']}>
            <LinearGradient
                colors={[colors.background, '#1a1f3a']}
                style={styles.gradient}
            >
                <ScrollView
                    contentContainerStyle={styles.scrollContent}
                    showsVerticalScrollIndicator={false}
                >
                    {/* Header */}
                    <View style={styles.header}>
                        <TouchableOpacity
                            style={styles.backButton}
                            onPress={handleNewAnalysis}
                        >
                            <Text style={styles.backButtonText}>← Back</Text>
                        </TouchableOpacity>
                        <Text style={styles.title}>Flood Risk Analysis</Text>
                    </View>

                    {/* Status Card */}
                    <Animated.View
                        style={[
                            styles.statusCard,
                            {
                                opacity: fadeAnim,
                                transform: [{ translateY: slideAnim }],
                            },
                        ]}
                    >
                        <LinearGradient
                            colors={
                                result?.isFloodRisk
                                    ? ['rgba(239, 68, 68, 0.2)', 'rgba(239, 68, 68, 0.05)']
                                    : ['rgba(16, 185, 129, 0.2)', 'rgba(16, 185, 129, 0.05)']
                            }
                            style={styles.statusGradient}
                        >
                            <Text style={styles.statusIcon}>
                                {getRiskIcon(result?.isFloodRisk)}
                            </Text>
                            <Text style={styles.statusTitle}>
                                {result?.isFloodRisk ? 'Flood Risk Detected' : 'Low Flood Risk'}
                            </Text>
                            <Text style={styles.statusSubtitle}>
                                Probability: {result?.floodProbability}%
                            </Text>
                            <Text style={styles.confidenceText}>
                                Confidence: {result?.confidence}%
                            </Text>
                        </LinearGradient>
                    </Animated.View>

                    {/* Weather Summary */}
                    <Animated.View
                        style={[
                            styles.detailCard,
                            {
                                opacity: fadeAnim,
                                transform: [{ translateY: slideAnim }],
                            },
                        ]}
                    >
                        <View style={styles.detailHeader}>
                            <Text style={styles.detailIcon}>🌦️</Text>
                            <Text style={styles.detailTitle}>Weather Summary</Text>
                        </View>

                        <View style={styles.weatherCompare}>
                            <View style={styles.weatherColumn}>
                                <Text style={styles.weatherLabel}>Today</Text>
                                <Text style={styles.weatherValue}>
                                    {Math.round(result?.weatherSummary?.current?.temp || 0)}°C
                                </Text>
                                <Text style={styles.weatherDetail}>
                                    💧 {result?.weatherSummary?.current?.humidity}%
                                </Text>
                                <Text style={styles.weatherDetail}>
                                    🌧️ {result?.weatherSummary?.current?.rainfall} mm
                                </Text>
                            </View>

                            <View style={styles.divider} />

                            <View style={styles.weatherColumn}>
                                <Text style={styles.weatherLabel}>Yesterday</Text>
                                <Text style={styles.weatherValue}>
                                    {Math.round(result?.weatherSummary?.yesterday?.temp || 0)}°C
                                </Text>
                                <Text style={styles.weatherDetail}>
                                    💧 {result?.weatherSummary?.yesterday?.humidity}%
                                </Text>
                                <Text style={styles.weatherDetail}>
                                    🌧️ {result?.weatherSummary?.yesterday?.rainfall} mm
                                </Text>
                            </View>
                        </View>
                    </Animated.View>

                    {/* Risk Factors */}
                    <Animated.View
                        style={[
                            styles.detailCard,
                            {
                                opacity: fadeAnim,
                                transform: [{ translateY: slideAnim }],
                            },
                        ]}
                    >
                        <View style={styles.detailHeader}>
                            <Text style={styles.detailIcon}>📊</Text>
                            <Text style={styles.detailTitle}>Risk Factors</Text>
                        </View>

                        {result?.isFloodRisk && (
                            <View style={styles.severityBadgeContainer}>
                                <Text style={styles.severityLabel}>Severity:</Text>
                                <View
                                    style={[
                                        styles.severityBadge,
                                        { backgroundColor: getSeverityColor(result?.severity) },
                                    ]}
                                >
                                    <Text style={styles.severityText}>{result?.severity}</Text>
                                </View>
                            </View>
                        )}

                        <View style={styles.factorsList}>
                            <View style={styles.factorItem}>
                                <Text style={styles.factorLabel}>Total Rainfall</Text>
                                <Text style={styles.factorValue}>{result?.factors?.rainfall?.toFixed(1)} mm</Text>
                            </View>
                            <View style={styles.factorItem}>
                                <Text style={styles.factorLabel}>Humidity</Text>
                                <Text style={styles.factorValue}>{result?.factors?.humidity}%</Text>
                            </View>
                            <View style={styles.factorItem}>
                                <Text style={styles.factorLabel}>Temperature</Text>
                                <Text style={styles.factorValue}>{result?.factors?.temperature?.toFixed(1)}°C</Text>
                            </View>
                            <View style={styles.factorItem}>
                                <Text style={styles.factorLabel}>Pressure</Text>
                                <Text style={styles.factorValue}>{result?.factors?.pressure} hPa</Text>
                            </View>
                        </View>
                    </Animated.View>

                    {/* Recommendations */}
                    <Animated.View
                        style={[
                            styles.detailCard,
                            {
                                opacity: fadeAnim,
                                transform: [{ translateY: slideAnim }],
                            },
                        ]}
                    >
                        <View style={styles.detailHeader}>
                            <Text style={styles.detailIcon}>💡</Text>
                            <Text style={styles.detailTitle}>Recommendations</Text>
                        </View>
                        <View style={styles.recommendationsList}>
                            {result?.recommendations?.map((recommendation, index) => (
                                <View key={index} style={styles.recommendationItem}>
                                    <Text style={styles.recommendationBullet}>•</Text>
                                    <Text style={styles.recommendationText}>
                                        {recommendation}
                                    </Text>
                                </View>
                            ))}
                        </View>
                    </Animated.View>

                    {/* Action Button */}
                    <Animated.View
                        style={[
                            styles.buttonContainer,
                            {
                                opacity: fadeAnim,
                                transform: [{ translateY: slideAnim }],
                            },
                        ]}
                    >
                        <CustomButton
                            title="Check Again"
                            icon="🔄"
                            onPress={handleNewAnalysis}
                            variant="primary"
                            style={styles.button}
                        />
                    </Animated.View>
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
        marginBottom: spacing.lg,
    },
    backButton: {
        marginBottom: spacing.md,
    },
    backButtonText: {
        ...typography.body,
        color: colors.primary,
        fontWeight: '600',
    },
    title: {
        ...typography.h1,
        color: colors.text,
    },
    statusCard: {
        marginBottom: spacing.lg,
        borderRadius: borderRadius.lg,
        overflow: 'hidden',
    },
    statusGradient: {
        padding: spacing.xl,
        alignItems: 'center',
        borderRadius: borderRadius.lg,
        borderWidth: 1,
        borderColor: colors.border,
    },
    statusIcon: {
        fontSize: 64,
        marginBottom: spacing.md,
    },
    statusTitle: {
        ...typography.h2,
        color: colors.text,
        marginBottom: spacing.xs,
    },
    statusSubtitle: {
        ...typography.body,
        color: colors.textSecondary,
        marginBottom: spacing.xs,
    },
    confidenceText: {
        ...typography.caption,
        color: colors.textSecondary,
    },
    detailCard: {
        backgroundColor: colors.surface,
        padding: spacing.lg,
        borderRadius: borderRadius.md,
        marginBottom: spacing.lg,
        ...shadows.sm,
    },
    detailHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: spacing.md,
        gap: spacing.sm,
    },
    detailIcon: {
        fontSize: 24,
    },
    detailTitle: {
        ...typography.h3,
        color: colors.text,
    },
    weatherCompare: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    weatherColumn: {
        flex: 1,
        alignItems: 'center',
    },
    weatherLabel: {
        ...typography.caption,
        color: colors.textSecondary,
        marginBottom: spacing.xs,
    },
    weatherValue: {
        ...typography.h2,
        color: colors.primary,
        marginBottom: spacing.sm,
    },
    weatherDetail: {
        ...typography.caption,
        color: colors.textSecondary,
        marginTop: spacing.xs,
    },
    divider: {
        width: 1,
        height: '100%',
        backgroundColor: colors.border,
        marginHorizontal: spacing.md,
    },
    severityBadgeContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: spacing.md,
        gap: spacing.sm,
    },
    severityLabel: {
        ...typography.body,
        color: colors.textSecondary,
    },
    severityBadge: {
        paddingVertical: spacing.sm,
        paddingHorizontal: spacing.lg,
        borderRadius: borderRadius.full,
    },
    severityText: {
        ...typography.body,
        color: colors.text,
        fontWeight: 'bold',
    },
    factorsList: {
        gap: spacing.sm,
    },
    factorItem: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        backgroundColor: colors.surfaceLight,
        padding: spacing.md,
        borderRadius: borderRadius.sm,
    },
    factorLabel: {
        ...typography.body,
        color: colors.textSecondary,
    },
    factorValue: {
        ...typography.body,
        color: colors.text,
        fontWeight: '600',
    },
    recommendationsList: {
        gap: spacing.sm,
    },
    recommendationItem: {
        flexDirection: 'row',
        gap: spacing.sm,
    },
    recommendationBullet: {
        ...typography.body,
        color: colors.primary,
        fontWeight: 'bold',
    },
    recommendationText: {
        ...typography.body,
        color: colors.textSecondary,
        flex: 1,
    },
    buttonContainer: {
        gap: spacing.md,
    },
    button: {
        width: '100%',
    },
    loadingContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        padding: spacing.xl,
    },
    loadingText: {
        ...typography.h2,
        color: colors.text,
        marginTop: spacing.lg,
        marginBottom: spacing.xs,
    },
    loadingSubtext: {
        ...typography.body,
        color: colors.textSecondary,
    },
    errorContainer: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        padding: spacing.xl,
    },
    errorIcon: {
        fontSize: 64,
        marginBottom: spacing.lg,
    },
    errorTitle: {
        ...typography.h2,
        color: colors.text,
        marginBottom: spacing.sm,
    },
    errorText: {
        ...typography.body,
        color: colors.textSecondary,
        textAlign: 'center',
        marginBottom: spacing.xl,
    },
    errorButtons: {
        width: '100%',
        gap: spacing.md,
    },
    errorButton: {
        width: '100%',
    },
});

export default ResultScreen;
