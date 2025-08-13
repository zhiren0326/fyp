import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

class TranslationService {
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  static const String _geminiEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  // Enhanced configuration for reliability
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const Duration _rateLimitDelay = Duration(milliseconds: 500); // Increased delay

  final Map<String, String> _translationCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(hours: 24);

  // Track API usage to avoid rate limits
  int _requestCount = 0;
  DateTime _lastRequestTime = DateTime.now();
  static const int _maxRequestsPerMinute = 50; // Conservative limit

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

  /// Make API request with comprehensive retry logic
  Future<http.Response> _makeReliableRequest(Map<String, dynamic> requestBody, {int retryCount = 0}) async {
    // Rate limiting check
    await _enforceRateLimit();

    try {
      print('Making translation request (attempt ${retryCount + 1}/$_maxRetries)');

      final response = await http.post(
        Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Flutter-Translation-App/1.0',
        },
        body: jsonEncode(requestBody),
      ).timeout(_requestTimeout);

      _requestCount++;
      _lastRequestTime = DateTime.now();

      // Handle different response codes
      if (response.statusCode == 200) {
        return response;
      } else if (response.statusCode == 429) {
        // Rate limited - wait longer and retry
        if (retryCount < _maxRetries - 1) {
          final waitTime = Duration(seconds: (retryCount + 1) * 5); // Exponential backoff
          print('Rate limited (429), waiting ${waitTime.inSeconds} seconds before retry...');
          await Future.delayed(waitTime);
          return await _makeReliableRequest(requestBody, retryCount: retryCount + 1);
        } else {
          throw Exception('Rate limit exceeded after $retryCount retries');
        }
      } else if (response.statusCode == 400) {
        // Bad request - likely content filtering or invalid input
        print('Bad request (400): ${response.body}');
        throw Exception('Invalid request - content may be blocked or too long');
      } else if (response.statusCode == 403) {
        // Forbidden - API key or quota issue
        print('Forbidden (403): ${response.body}');
        throw Exception('API key issue or quota exceeded');
      } else if (response.statusCode >= 500 && retryCount < _maxRetries - 1) {
        // Server error - retry
        final waitTime = Duration(seconds: (retryCount + 1) * 2);
        print('Server error (${response.statusCode}), retrying in ${waitTime.inSeconds} seconds...');
        await Future.delayed(waitTime);
        return await _makeReliableRequest(requestBody, retryCount: retryCount + 1);
      } else {
        throw Exception('API request failed with status ${response.statusCode}: ${response.body}');
      }
    } on SocketException catch (e) {
      if (retryCount < _maxRetries - 1) {
        final waitTime = Duration(seconds: (retryCount + 1) * 2);
        print('Network error, retrying in ${waitTime.inSeconds} seconds: $e');
        await Future.delayed(waitTime);
        return await _makeReliableRequest(requestBody, retryCount: retryCount + 1);
      } else {
        throw Exception('Network error after $retryCount retries: $e');
      }
    } on TimeoutException catch (e) {
      if (retryCount < _maxRetries - 1) {
        final waitTime = Duration(seconds: (retryCount + 1) * 2);
        print('Request timeout, retrying in ${waitTime.inSeconds} seconds: $e');
        await Future.delayed(waitTime);
        return await _makeReliableRequest(requestBody, retryCount: retryCount + 1);
      } else {
        throw Exception('Request timeout after $retryCount retries: $e');
      }
    } on HandshakeException catch (e) {
      if (retryCount < _maxRetries - 1) {
        final waitTime = Duration(seconds: (retryCount + 1) * 3);
        print('SSL handshake error, retrying in ${waitTime.inSeconds} seconds: $e');
        await Future.delayed(waitTime);
        return await _makeReliableRequest(requestBody, retryCount: retryCount + 1);
      } else {
        throw Exception('SSL handshake failed after $retryCount retries: $e');
      }
    }
  }

  /// Enforce rate limiting to prevent API throttling
  Future<void> _enforceRateLimit() async {
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastRequestTime);

    // Reset counter if more than a minute has passed
    if (timeSinceLastRequest.inMinutes >= 1) {
      _requestCount = 0;
    }

    // If we're approaching the rate limit, add a delay
    if (_requestCount >= _maxRequestsPerMinute) {
      final waitTime = Duration(seconds: 60 - timeSinceLastRequest.inSeconds);
      if (waitTime.inSeconds > 0) {
        print('Rate limit protection: waiting ${waitTime.inSeconds} seconds...');
        await Future.delayed(waitTime);
        _requestCount = 0;
      }
    }

    // Always add a small delay between requests
    if (timeSinceLastRequest < _rateLimitDelay) {
      await Future.delayed(_rateLimitDelay - timeSinceLastRequest);
    }
  }

  /// Validate and prepare text for translation
  String _prepareTextForTranslation(String text) {
    if (text.isEmpty) return text;

    // Trim whitespace
    text = text.trim();

    // Check length (Gemini has token limits)
    if (text.length > 5000) {
      print('Warning: Text is very long (${text.length} chars), truncating...');
      text = text.substring(0, 5000) + '...';
    }

    return text;
  }

  /// Enhanced translate text with better error handling
  Future<String> translateText(String text, String targetLanguage) async {
    if (text.isEmpty || targetLanguage == 'en') return text;

    // Prepare text
    text = _prepareTextForTranslation(text);

    // Check cache first
    final cacheKey = '${text.hashCode}_$targetLanguage';
    if (_translationCache.containsKey(cacheKey)) {
      final cacheTime = _cacheTimestamps[cacheKey];
      if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheExpiry) {
        print('Cache hit for translation');
        return _translationCache[cacheKey]!;
      }
    }

    try {
      final languageName = _languageNames[targetLanguage] ?? targetLanguage;

      final requestBody = {
        'contents': [{
          'parts': [{
            'text': 'You are a professional translator. Translate the following text to $languageName.\nPreserve the original meaning, tone, and context. Keep emojis and formatting.\nOnly provide the translation, nothing else.\n\nText to translate: "$text"\n\nTranslation:'
          }]
        }],
        'generationConfig': {
          'temperature': 0.3,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 1024,
        },
        'safetySettings': [
          {
            'category': 'HARM_CATEGORY_HARASSMENT',
            'threshold': 'BLOCK_NONE'
          },
          {
            'category': 'HARM_CATEGORY_HATE_SPEECH',
            'threshold': 'BLOCK_NONE'
          },
          {
            'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            'threshold': 'BLOCK_NONE'
          },
          {
            'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
            'threshold': 'BLOCK_NONE'
          }
        ]
      };

      final response = await _makeReliableRequest(requestBody);

      final data = jsonDecode(response.body);

      // Enhanced response parsing with better error handling
      if (data['candidates'] == null || data['candidates'].isEmpty) {
        throw Exception('No translation candidates returned - content may be blocked');
      }

      final candidate = data['candidates'][0];
      if (candidate['content'] == null || candidate['content']['parts'] == null) {
        throw Exception('Invalid response structure from API');
      }

      final translatedText = candidate['content']['parts'][0]['text']?.trim() ?? '';

      if (translatedText.isEmpty) {
        throw Exception('Empty translation returned - content may be filtered');
      }

      // Clean up the response
      final cleanTranslation = _cleanTranslationResponse(translatedText);

      // Cache the translation
      _translationCache[cacheKey] = cleanTranslation;
      _cacheTimestamps[cacheKey] = DateTime.now();

      print('Translation successful: ${text.substring(0, text.length > 50 ? 50 : text.length)}... -> ${cleanTranslation.substring(0, cleanTranslation.length > 50 ? 50 : cleanTranslation.length)}...');

      return cleanTranslation;

    } catch (e) {
      print('Translation error: $e');

      // For debugging: log the exact error
      if (e.toString().contains('Rate limit') || e.toString().contains('429')) {
        print('Rate limiting detected - consider increasing delays between requests');
      } else if (e.toString().contains('403') || e.toString().contains('quota')) {
        print('API quota/permission issue - check your API key and billing');
      } else if (e.toString().contains('400') || e.toString().contains('blocked')) {
        print('Content filtering issue - text may contain blocked content');
      }

      // Return original text instead of throwing for better UX
      return text;
    }
  }

  /// Translate multiple messages with enhanced batch handling
  Future<List<Map<String, String>>> translateMessagesBatch(
      List<Map<String, dynamic>> messages,
      String targetLanguage, {
        Function(int current, int total)? onProgress,
        bool continueOnError = true,
      }) async {
    List<Map<String, String>> translatedMessages = [];

    print('Starting batch translation of ${messages.length} messages');

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
            'status': 'success',
          });
        } else {
          translatedMessages.add({
            'messageId': messageData['id'] ?? '',
            'original': originalText,
            'translation': originalText,
            'targetLanguage': targetLanguage,
            'status': 'skipped_empty',
          });
        }

        // Report progress
        if (onProgress != null) {
          onProgress(i + 1, messages.length);
        }

        // Enhanced delay to prevent rate limiting
        await Future.delayed(_rateLimitDelay);

      } catch (e) {
        print('Failed to translate message ${i + 1}: $e');
        final messageData = messages[i];

        translatedMessages.add({
          'messageId': messageData['id'] ?? '',
          'original': messageData['text'] ?? '',
          'translation': messageData['text'] ?? '', // Fallback to original
          'targetLanguage': targetLanguage,
          'status': 'error',
          'error': e.toString(),
        });

        if (!continueOnError) {
          break; // Stop batch processing on error
        }

        // Add extra delay after error
        await Future.delayed(Duration(seconds: 2));
      }
    }

    print('Batch translation completed: ${translatedMessages.where((m) => m['status'] == 'success').length}/${messages.length} successful');
    return translatedMessages;
  }

  /// Get translation service health status
  Map<String, dynamic> getServiceHealth() {
    final now = DateTime.now();
    final cacheSize = _translationCache.length;
    final requestsInLastMinute = now.difference(_lastRequestTime).inMinutes < 1 ? _requestCount : 0;

    return {
      'status': requestsInLastMinute < _maxRequestsPerMinute ? 'healthy' : 'rate_limited',
      'cacheSize': cacheSize,
      'requestsInLastMinute': requestsInLastMinute,
      'maxRequestsPerMinute': _maxRequestsPerMinute,
      'lastRequestTime': _lastRequestTime.toIso8601String(),
    };
  }

  /// Test API connectivity
  Future<bool> testApiConnection() async {
    try {
      print('Testing API connection...');
      final result = await translateText('Hello', 'es');
      print('API test result: $result');
      return result.isNotEmpty && result != 'Hello';
    } catch (e) {
      print('API test failed: $e');
      return false;
    }
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
          'status': 'skipped_empty',
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
        'status': 'success',
      };
    } catch (e) {
      return {
        'messageId': messageData['id'] ?? '',
        'original': messageData['text'] ?? '',
        'translation': messageData['text'] ?? '',
        'targetLanguage': targetLanguage,
        'status': 'error',
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

      final requestBody = {
        'contents': [{
          'parts': [{
            'text': 'You are an expert translator with deep understanding of cultural nuances and chat communication.\n${contextPrompt}Translate the following message to $languageName, considering:\n- Informal chat language and slang\n- Cultural appropriateness\n- Emojis and emoticons (preserve them)\n- Tone and formality level\n- Context-specific terminology\n\nOnly provide the translation, nothing else.\n\nMessage: "$text"\n\nTranslation:'
          }]
        }],
        'generationConfig': {
          'temperature': 0.4,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 1024,
        }
      };

      final response = await _makeReliableRequest(requestBody);
      final data = jsonDecode(response.body);
      final translatedText = data['candidates'][0]['content']['parts'][0]['text'].trim();
      return _cleanTranslationResponse(translatedText);
    } catch (e) {
      print('Smart translation error: $e');
      // Fallback to regular translation
      return await translateText(text, targetLanguage);
    }
  }

  /// Translate with original text preservation for display
  Future<Map<String, String>> translateWithOriginal(String text, String targetLanguage) async {
    if (text.isEmpty) {
      return {'original': text, 'translation': text, 'status': 'skipped_empty'};
    }

    try {
      final translation = await translateText(text, targetLanguage);
      return {
        'original': text,
        'translation': translation,
        'targetLanguage': targetLanguage,
        'languageName': _languageNames[targetLanguage] ?? targetLanguage,
        'status': 'success',
      };
    } catch (e) {
      return {
        'original': text,
        'translation': text,
        'error': e.toString(),
        'status': 'error',
      };
    }
  }

  /// Detect language of text
  Future<String> detectLanguage(String text) async {
    if (text.isEmpty) return 'en';

    try {
      final requestBody = {
        'contents': [{
          'parts': [{
            'text': 'Detect the language of the following text and respond with only the 2-letter language code (like \'en\', \'es\', \'fr\', etc.).\n\nText: "$text"\n\nLanguage code:'
          }]
        }],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 10,
        }
      };

      final response = await _makeReliableRequest(requestBody);
      final data = jsonDecode(response.body);
      final languageCode = data['candidates'][0]['content']['parts'][0]['text'].trim().toLowerCase();

      // Validate the language code
      if (_languageNames.containsKey(languageCode)) {
        return languageCode;
      } else {
        return 'en'; // Default to English if detection fails
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
          'status': 'success',
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
    print('Translation cache cleared');
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

      if (message['status'] != 'success') {
        buffer.writeln('Status: ${message['status']}');
      }

      buffer.writeln();
    }

    return buffer.toString();
  }
}