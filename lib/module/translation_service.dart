import 'dart:convert';
import 'package:http/http.dart' as http;

class TranslationService {
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  static const String _geminiEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';

  final Map<String, String> _translationCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(hours: 24);

  final Map<String, String> _languageNames = {
    'en': 'English',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'id': 'Indonesian',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
  };

  /// Translate text to target language using Gemini API
  Future<String> translateText(String text, String targetLanguage) async {
    if (text.isEmpty || targetLanguage == 'en') return text;

    // Check cache first
    final cacheKey = '${text}_$targetLanguage';
    if (_translationCache.containsKey(cacheKey)) {
      final cacheTime = _cacheTimestamps[cacheKey];
      if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheExpiry) {
        return _translationCache[cacheKey]!;
      }
    }

    try {
      final languageName = _languageNames[targetLanguage] ?? targetLanguage;

      final response = await http.post(
        Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': '''
You are a professional translator. Translate the following text to $languageName.
Preserve the original meaning, tone, and context. Keep emojis and formatting.
Only provide the translation, nothing else.

Text to translate: "$text"

Translation:'''
            }]
          }],
          'generationConfig': {
            'temperature': 0.3,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 1024,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translatedText = data['candidates'][0]['content']['parts'][0]['text'].trim();

        // Clean up the response
        final cleanTranslation = _cleanTranslationResponse(translatedText);

        // Cache the translation
        _translationCache[cacheKey] = cleanTranslation;
        _cacheTimestamps[cacheKey] = DateTime.now();

        return cleanTranslation;
      } else {
        print('Translation API error: ${response.statusCode} - ${response.body}');
        throw Exception('Translation failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Translation error: $e');
      throw Exception('Translation failed: $e');
    }
  }

  /// Translate multiple messages in batch with progress callback
  Future<List<Map<String, String>>> translateMessagesBatch(
      List<Map<String, dynamic>> messages,
      String targetLanguage, {
        Function(int current, int total)? onProgress,
      }) async {
    List<Map<String, String>> translatedMessages = [];

    for (int i = 0; i < messages.length; i++) {
      try {
        final messageData = messages[i];
        final originalText = messageData['text'] ?? '';

        if (originalText.isNotEmpty) {
          final translation = await translateText(originalText, targetLanguage);
          translatedMessages.add({
            'messageId': messageData['id'] ?? '',
            'original': originalText,
            'translation': translation,
            'targetLanguage': targetLanguage,
          });
        } else {
          translatedMessages.add({
            'messageId': messageData['id'] ?? '',
            'original': originalText,
            'translation': originalText,
            'targetLanguage': targetLanguage,
          });
        }

        // Report progress
        if (onProgress != null) {
          onProgress(i + 1, messages.length);
        }

        // Small delay to avoid API rate limits
        await Future.delayed(const Duration(milliseconds: 200));

      } catch (e) {
        print('Failed to translate message ${i + 1}: $e');
        final messageData = messages[i];
        translatedMessages.add({
          'messageId': messageData['id'] ?? '',
          'original': messageData['text'] ?? '',
          'translation': messageData['text'] ?? '',
          'targetLanguage': targetLanguage,
          'error': e.toString(),
        });
      }
    }

    return translatedMessages;
  }

  /// Translate a single message with metadata
  Future<Map<String, String>> translateMessage(
      Map<String, dynamic> messageData,
      String targetLanguage,
      ) async {
    try {
      final originalText = messageData['text'] ?? '';

      if (originalText.isEmpty) {
        return {
          'messageId': messageData['id'] ?? '',
          'original': originalText,
          'translation': originalText,
          'targetLanguage': targetLanguage,
        };
      }

      final translation = await translateText(originalText, targetLanguage);

      return {
        'messageId': messageData['id'] ?? '',
        'original': originalText,
        'translation': translation,
        'targetLanguage': targetLanguage,
        'senderName': messageData['senderName'] ?? '',
        'timestamp': messageData['timestamp']?.toString() ?? '',
      };
    } catch (e) {
      return {
        'messageId': messageData['id'] ?? '',
        'original': messageData['text'] ?? '',
        'translation': messageData['text'] ?? '',
        'targetLanguage': targetLanguage,
        'error': e.toString(),
      };
    }
  }

  /// Smart translation that detects context and adjusts accordingly
  Future<String> smartTranslate(
      String text,
      String targetLanguage, {
        String? context,
        String? senderName,
        bool isGroupMessage = false,
      }) async {
    if (text.isEmpty) return text;

    try {
      final languageName = _languageNames[targetLanguage] ?? targetLanguage;

      String contextPrompt = '';
      if (context != null) {
        contextPrompt += 'Context: $context\n';
      }
      if (senderName != null) {
        contextPrompt += 'Sender: $senderName\n';
      }
      if (isGroupMessage) {
        contextPrompt += 'This is a group chat message.\n';
      }

      final response = await http.post(
        Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': '''
You are an expert translator with deep understanding of cultural nuances and chat communication.
${contextPrompt}
Translate the following message to $languageName, considering:
- Informal chat language and slang
- Cultural appropriateness
- Emojis and emoticons (preserve them)
- Tone and formality level
- Context-specific terminology

Only provide the translation, nothing else.

Message: "$text"

Translation:'''
            }]
          }],
          'generationConfig': {
            'temperature': 0.4,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 1024,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translatedText = data['candidates'][0]['content']['parts'][0]['text'].trim();
        return _cleanTranslationResponse(translatedText);
      } else {
        throw Exception('Smart translation failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Smart translation error: $e');
      // Fallback to regular translation
      return await translateText(text, targetLanguage);
    }
  }

  /// Translate with original text preservation for display
  Future<Map<String, String>> translateWithOriginal(String text, String targetLanguage) async {
    if (text.isEmpty) {
      return {'original': text, 'translation': text};
    }

    try {
      final translation = await translateText(text, targetLanguage);
      return {
        'original': text,
        'translation': translation,
        'targetLanguage': targetLanguage,
        'languageName': _languageNames[targetLanguage] ?? targetLanguage,
      };
    } catch (e) {
      return {
        'original': text,
        'translation': text,
        'error': e.toString(),
      };
    }
  }

  /// Detect language of text
  Future<String> detectLanguage(String text) async {
    if (text.isEmpty) return 'en';

    try {
      final response = await http.post(
        Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': '''
Detect the language of the following text and respond with only the 2-letter language code (like 'en', 'es', 'fr', etc.).

Text: "$text"

Language code:'''
            }]
          }],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 10,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final languageCode = data['candidates'][0]['content']['parts'][0]['text'].trim().toLowerCase();

        // Validate the language code
        if (_languageNames.containsKey(languageCode)) {
          return languageCode;
        } else {
          return 'en'; // Default to English if detection fails
        }
      } else {
        print('Language detection error: ${response.statusCode}');
        return 'en';
      }
    } catch (e) {
      print('Language detection error: $e');
      return 'en';
    }
  }

  /// Auto-translate incoming messages based on detected language
  Future<Map<String, String>?> autoTranslateIfNeeded(
      String text,
      String userPreferredLanguage, {
        String? senderName,
        bool isGroupMessage = false,
      }) async {
    if (text.isEmpty) return null;

    try {
      // Detect the language of the incoming message
      final detectedLanguage = await detectLanguage(text);

      // If the detected language is different from user's preferred language, translate
      if (detectedLanguage != userPreferredLanguage) {
        final translation = await smartTranslate(
          text,
          userPreferredLanguage,
          senderName: senderName,
          isGroupMessage: isGroupMessage,
        );

        return {
          'original': text,
          'translation': translation,
          'detectedLanguage': detectedLanguage,
          'targetLanguage': userPreferredLanguage,
          'detectedLanguageName': _languageNames[detectedLanguage] ?? detectedLanguage,
          'targetLanguageName': _languageNames[userPreferredLanguage] ?? userPreferredLanguage,
        };
      }

      return null; // No translation needed
    } catch (e) {
      print('Auto-translation error: $e');
      return null;
    }
  }

  /// Clean translation response by removing common prefixes/suffixes
  String _cleanTranslationResponse(String response) {
    String cleaned = response.trim();

    // Remove common prefixes
    final prefixes = [
      'Translation:',
      'Translated text:',
      'Here is the translation:',
      'The translation is:',
      'Translate:',
      'Result:',
    ];

    for (String prefix in prefixes) {
      if (cleaned.toLowerCase().startsWith(prefix.toLowerCase())) {
        cleaned = cleaned.substring(prefix.length).trim();
      }
    }

    // Remove quotes if the entire response is quoted
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }

    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }

    return cleaned.trim();
  }

  /// Get supported languages
  Map<String, String> getSupportedLanguages() {
    return Map.from(_languageNames);
  }

  /// Check if language is supported
  bool isLanguageSupported(String languageCode) {
    return _languageNames.containsKey(languageCode);
  }

  /// Clear translation cache
  void clearCache() {
    _translationCache.clear();
    _cacheTimestamps.clear();
  }

  /// Get cache statistics
  Map<String, int> getCacheStats() {
    // Clean expired entries
    final now = DateTime.now();
    final expiredKeys = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) > _cacheExpiry)
        .map((entry) => entry.key)
        .toList();

    for (String key in expiredKeys) {
      _translationCache.remove(key);
      _cacheTimestamps.remove(key);
    }

    return {
      'totalEntries': _translationCache.length,
      'expiredRemoved': expiredKeys.length,
    };
  }

  /// Bulk translate for conversation history
  Future<List<Map<String, String>>> translateConversationHistory(
      List<Map<String, dynamic>> messages,
      String targetLanguage, {
        int? maxMessages,
        Function(int current, int total)? onProgress,
      }) async {
    // Limit messages if specified
    final messagesToTranslate = maxMessages != null
        ? messages.take(maxMessages).toList()
        : messages;

    return await translateMessagesBatch(
      messagesToTranslate,
      targetLanguage,
      onProgress: onProgress,
    );
  }

  /// Export translated conversation
  Future<String> exportTranslatedConversation(
      List<Map<String, String>> translatedMessages,
      String conversationTitle,
      ) async {
    final buffer = StringBuffer();
    buffer.writeln('Translated Conversation: $conversationTitle');
    buffer.writeln('Exported on: ${DateTime.now().toString()}');
    buffer.writeln('=' * 50);
    buffer.writeln();

    for (final message in translatedMessages) {
      if (message['senderName']?.isNotEmpty == true) {
        buffer.writeln('${message['senderName']}:');
      }

      if (message['original']?.isNotEmpty == true) {
        buffer.writeln('Original: ${message['original']}');
      }

      if (message['translation']?.isNotEmpty == true) {
        buffer.writeln('Translation: ${message['translation']}');
      }

      if (message['timestamp']?.isNotEmpty == true) {
        buffer.writeln('Time: ${message['timestamp']}');
      }

      buffer.writeln();
    }

    return buffer.toString();
  }
}