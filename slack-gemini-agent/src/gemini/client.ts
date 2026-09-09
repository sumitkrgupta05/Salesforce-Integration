import { GoogleGenAI } from '@google/genai';
import { loadConfig } from '../config.js';

let aiInstance: GoogleGenAI | null = null;

/**
 * Returns a singleton instance of GoogleGenAI initialized with the Google AI Studio API key.
 */
export function getGeminiClient(): GoogleGenAI {
  if (!aiInstance) {
    const config = loadConfig(false);
    aiInstance = new GoogleGenAI({
      apiKey: config.geminiApiKey,
    });
  }
  return aiInstance;
}
