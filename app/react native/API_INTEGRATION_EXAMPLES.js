/**
 * API Integration Example
 * 
 * This file shows different ways to integrate your AI model with the app.
 * Choose the method that best fits your backend setup.
 */

import axios from 'axios';

// ============================================
// EXAMPLE 1: Simple REST API
// ============================================

export const simpleAPIIntegration = async (imageUri) => {
    const API_URL = 'https://your-backend.com/api/detect';

    const formData = new FormData();
    const filename = imageUri.split('/').pop();
    const match = /\.(\w+)$/.exec(filename);
    const type = match ? `image/${match[1]}` : 'image/jpeg';

    formData.append('image', {
        uri: imageUri,
        name: filename,
        type: type,
    });

    try {
        const response = await axios.post(API_URL, formData, {
            headers: {
                'Content-Type': 'multipart/form-data',
            },
            timeout: 30000,
        });

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        return {
            success: false,
            error: error.message,
        };
    }
};

// ============================================
// EXAMPLE 2: API with Authentication Token
// ============================================

export const authenticatedAPIIntegration = async (imageUri, authToken) => {
    const API_URL = 'https://your-backend.com/api/detect';

    const formData = new FormData();
    const filename = imageUri.split('/').pop();
    const match = /\.(\w+)$/.exec(filename);
    const type = match ? `image/${match[1]}` : 'image/jpeg';

    formData.append('image', {
        uri: imageUri,
        name: filename,
        type: type,
    });

    try {
        const response = await axios.post(API_URL, formData, {
            headers: {
                'Content-Type': 'multipart/form-data',
                'Authorization': `Bearer ${authToken}`,
            },
            timeout: 30000,
        });

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        return {
            success: false,
            error: error.message,
        };
    }
};

// ============================================
// EXAMPLE 3: Base64 Image Upload
// ============================================

import * as FileSystem from 'expo-file-system';

export const base64APIIntegration = async (imageUri) => {
    const API_URL = 'https://your-backend.com/api/detect';

    try {
        // Convert image to base64
        const base64 = await FileSystem.readAsStringAsync(imageUri, {
            encoding: FileSystem.EncodingType.Base64,
        });

        const response = await axios.post(
            API_URL,
            {
                image: base64,
                filename: imageUri.split('/').pop(),
            },
            {
                headers: {
                    'Content-Type': 'application/json',
                },
                timeout: 30000,
            }
        );

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        return {
            success: false,
            error: error.message,
        };
    }
};

// ============================================
// EXAMPLE 4: AWS S3 + Lambda Integration
// ============================================

export const awsIntegration = async (imageUri) => {
    try {
        // Step 1: Get presigned URL
        const presignResponse = await axios.get(
            'https://your-api.com/get-upload-url'
        );
        const { uploadUrl, fileKey } = presignResponse.data;

        // Step 2: Upload to S3
        const imageBlob = await fetch(imageUri).then(r => r.blob());
        await axios.put(uploadUrl, imageBlob, {
            headers: {
                'Content-Type': 'image/jpeg',
            },
        });

        // Step 3: Trigger analysis
        const analysisResponse = await axios.post(
            'https://your-api.com/analyze',
            { fileKey }
        );

        return {
            success: true,
            data: analysisResponse.data,
        };
    } catch (error) {
        return {
            success: false,
            error: error.message,
        };
    }
};

// ============================================
// EXAMPLE 5: Google Cloud Functions
// ============================================

export const googleCloudIntegration = async (imageUri) => {
    const CLOUD_FUNCTION_URL = 'https://region-project.cloudfunctions.net/detectFlood';

    const formData = new FormData();
    const filename = imageUri.split('/').pop();
    const match = /\.(\w+)$/.exec(filename);
    const type = match ? `image/${match[1]}` : 'image/jpeg';

    formData.append('image', {
        uri: imageUri,
        name: filename,
        type: type,
    });

    try {
        const response = await axios.post(CLOUD_FUNCTION_URL, formData, {
            headers: {
                'Content-Type': 'multipart/form-data',
            },
            timeout: 30000,
        });

        return {
            success: true,
            data: response.data,
        };
    } catch (error) {
        return {
            success: false,
            error: error.message,
        };
    }
};

// ============================================
// EXAMPLE 6: Custom Backend with Retry Logic
// ============================================

export const robustAPIIntegration = async (imageUri, maxRetries = 3) => {
    const API_URL = 'https://your-backend.com/api/detect';

    const formData = new FormData();
    const filename = imageUri.split('/').pop();
    const match = /\.(\w+)$/.exec(filename);
    const type = match ? `image/${match[1]}` : 'image/jpeg';

    formData.append('image', {
        uri: imageUri,
        name: filename,
        type: type,
    });

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            const response = await axios.post(API_URL, formData, {
                headers: {
                    'Content-Type': 'multipart/form-data',
                },
                timeout: 30000,
            });

            return {
                success: true,
                data: response.data,
            };
        } catch (error) {
            if (attempt === maxRetries) {
                return {
                    success: false,
                    error: `Failed after ${maxRetries} attempts: ${error.message}`,
                };
            }

            // Wait before retrying (exponential backoff)
            await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
        }
    }
};

// ============================================
// RESPONSE FORMAT TRANSFORMER
// ============================================

/**
 * If your API returns a different format, use this transformer
 */
export const transformAPIResponse = (apiResponse) => {
    // Example: Your API returns different field names
    return {
        isFlood: apiResponse.flood_detected,
        confidence: apiResponse.confidence_score,
        severity: apiResponse.flood_severity,
        waterLevel: apiResponse.water_percentage,
        recommendations: apiResponse.safety_tips,
    };
};

// ============================================
// USAGE INSTRUCTIONS
// ============================================

/**
 * TO USE ANY OF THESE EXAMPLES:
 * 
 * 1. Copy the function you want to use
 * 2. Paste it into services/api.js
 * 3. Rename it to 'detectFlood'
 * 4. Update the API_URL with your actual endpoint
 * 5. Modify the request/response format if needed
 * 6. Import and use in ResultScreen.js
 * 
 * Example in ResultScreen.js:
 * 
 * import { detectFlood } from '../services/api';
 * 
 * const response = await detectFlood(imageUri);
 * if (response.success) {
 *   setResult(response.data);
 * }
 */
