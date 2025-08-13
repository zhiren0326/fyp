import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class FileService {
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  static const String _geminiEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  // Network configuration
  static const Duration _timeoutDuration = Duration(seconds: 60);
  static const int _maxRetries = 3;

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

  /// Create HTTP client with proper configuration
  http.Client _createHttpClient() {
    final client = http.Client();
    return client;
  }

  /// Make API request with retry logic and proper error handling
  Future<http.Response> _makeApiRequest(String url, Map<String, dynamic> body, {int retryCount = 0}) async {
    final client = _createHttpClient();

    try {
      print('Making API request (attempt ${retryCount + 1}/$_maxRetries)');

      final response = await client.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Flutter-App/1.0',
        },
        body: jsonEncode(body),
      ).timeout(_timeoutDuration);

      print('API Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return response;
      } else if (response.statusCode == 429 && retryCount < _maxRetries - 1) {
        // Rate limited, wait and retry
        print('Rate limited, waiting before retry...');
        await Future.delayed(Duration(seconds: (retryCount + 1) * 2));
        return await _makeApiRequest(url, body, retryCount: retryCount + 1);
      } else {
        throw HttpException('API request failed with status ${response.statusCode}: ${response.body}');
      }
    } on SocketException catch (e) {
      print('Socket error: $e');
      if (retryCount < _maxRetries - 1) {
        print('Retrying due to socket error...');
        await Future.delayed(Duration(seconds: (retryCount + 1) * 2));
        return await _makeApiRequest(url, body, retryCount: retryCount + 1);
      }
      throw SocketException('Network error: $e');
    } on HandshakeException catch (e) {
      print('SSL Handshake error: $e');
      if (retryCount < _maxRetries - 1) {
        print('Retrying due to handshake error...');
        await Future.delayed(Duration(seconds: (retryCount + 1) * 3));
        return await _makeApiRequest(url, body, retryCount: retryCount + 1);
      }
      throw HandshakeException('SSL Handshake failed: $e');
    } on TimeoutException catch (e) {
      print('Timeout error: $e');
      if (retryCount < _maxRetries - 1) {
        print('Retrying due to timeout...');
        await Future.delayed(Duration(seconds: (retryCount + 1) * 2));
        return await _makeApiRequest(url, body, retryCount: retryCount + 1);
      }
      throw TimeoutException('Request timeout: ${e.message}', e.duration);
    } finally {
      client.close();
    }
  }

  /// Enhanced document translation with fallback to text file
  Future<File?> translateDocumentEnhanced(PlatformFile file, String targetLanguage, String languageName) async {
    try {
      print('Starting enhanced document translation for: ${file.name}');

      // Check file size (limit to 10MB for API)
      final fileSize = await File(file.path!).length();
      print('File size: ${getFileSizeString(fileSize)}');

      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('File too large (${getFileSizeString(fileSize)}). Maximum size: 10MB');
      }

      // Extract text from the document
      String content = await _extractTextFromFile(file);
      print('Extracted content length: ${content.length}');

      if (content.isEmpty) {
        throw Exception('Could not extract text from file');
      }

      // Translate the content
      print('Starting translation to: $languageName');
      String translatedContent = await _translateDocumentContent(content, targetLanguage, languageName);
      print('Translated content length: ${translatedContent.length}');

      if (translatedContent.isEmpty) {
        throw Exception('Translation returned empty content');
      }

      // Try to create text file (always works regardless of character encoding)
      final textFile = await createTranslatedTextFile(
        originalFileName: file.name,
        originalContent: content,
        translatedContent: translatedContent,
        targetLanguage: languageName,
      );

      print('Text file created successfully at: ${textFile.path}');
      return textFile;

    } catch (e) {
      print('Document translation error: $e');
      throw Exception('Failed to translate document: $e');
    }
  }

  /// Create a simple text file as an alternative to PDF when font issues occur
  Future<File> createTranslatedTextFile({
    required String originalFileName,
    required String originalContent,
    required String translatedContent,
    required String targetLanguage,
  }) async {
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    final buffer = StringBuffer();
    buffer.writeln('=' * 60);
    buffer.writeln('DOCUMENT TRANSLATION');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln('Original File: $originalFileName');
    buffer.writeln('Translated to: $targetLanguage');
    buffer.writeln('Translation Date: $formattedDate');
    buffer.writeln();
    buffer.writeln('=' * 60);
    buffer.writeln('ORIGINAL CONTENT');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln(originalContent);
    buffer.writeln();
    buffer.writeln('=' * 60);
    buffer.writeln('TRANSLATED CONTENT ($targetLanguage)');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln(translatedContent);
    buffer.writeln();
    buffer.writeln('=' * 60);
    buffer.writeln('Translated by AI Assistant');
    buffer.writeln('=' * 60);

    // Save as text file
    final directory = await getTemporaryDirectory();
    final textFile = File('${directory.path}/translated_${originalFileName.replaceAll(RegExp(r'\.[^.]*$'), '')}.txt');
    await textFile.writeAsString(buffer.toString(), encoding: utf8);

    return textFile;
  }

  /// Translate document and return as PDF (kept for backward compatibility)
  Future<File?> translateDocument(PlatformFile file, String targetLanguage, String languageName) async {
    // Use the enhanced version but try to create PDF
    try {
      print('Starting document translation for: ${file.name}');

      // Check file size (limit to 10MB for API)
      final fileSize = await File(file.path!).length();
      print('File size: ${getFileSizeString(fileSize)}');

      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('File too large (${getFileSizeString(fileSize)}). Maximum size: 10MB');
      }

      // Extract text from the document
      String content = await _extractTextFromFile(file);
      print('Extracted content length: ${content.length}');

      if (content.isEmpty) {
        throw Exception('Could not extract text from file');
      }

      // Translate the content
      print('Starting translation to: $languageName');
      String translatedContent = await _translateDocumentContent(content, targetLanguage, languageName);
      print('Translated content length: ${translatedContent.length}');

      if (translatedContent.isEmpty) {
        throw Exception('Translation returned empty content');
      }

      // Create simple PDF with basic text only (to avoid font issues)
      final pdf = await _createSimpleTranslatedPDF(
        originalFileName: file.name,
        originalContent: content,
        translatedContent: translatedContent,
        targetLanguage: languageName,
      );

      // Save PDF to temporary directory
      final directory = await getTemporaryDirectory();
      final pdfFile = File('${directory.path}/translated_${file.name.replaceAll(RegExp(r'\.[^.]*$'), '')}.pdf');
      await pdfFile.writeAsBytes(pdf);

      print('PDF created successfully at: ${pdfFile.path}');
      return pdfFile;
    } catch (e) {
      print('Document translation error: $e');
      throw Exception('Failed to translate document: $e');
    }
  }

  /// Extract text from various file formats
  Future<String> _extractTextFromFile(PlatformFile file) async {
    final fileBytes = await File(file.path!).readAsBytes();
    final extension = file.extension?.toLowerCase();

    print('Extracting text from ${extension?.toUpperCase()} file: ${file.name}');

    switch (extension) {
      case 'txt':
        return utf8.decode(fileBytes);

      case 'pdf':
        return await _extractTextFromPDF(fileBytes);

      case 'doc':
      case 'docx':
        return await _extractTextFromWord(fileBytes);

      default:
        throw Exception('Unsupported file format: $extension');
    }
  }

  /// Extract text from PDF with multiple fallback methods
  Future<String> _extractTextFromPDF(Uint8List pdfBytes) async {
    print('Extracting text from PDF using Gemini API');

    // Check if PDF is too large
    if (pdfBytes.length > 5 * 1024 * 1024) {
      throw Exception('PDF file too large (${getFileSizeString(pdfBytes.length)}). Maximum size for PDF extraction: 5MB');
    }

    try {
      final base64Pdf = base64Encode(pdfBytes);
      print('PDF encoded to base64, size: ${base64Pdf.length} characters');

      final requestBody = {
        'contents': [{
          'parts': [
            {
              'inline_data': {
                'mime_type': 'application/pdf',
                'data': base64Pdf,
              }
            },
            {
              'text': 'Extract all the text content from this PDF document. Preserve the structure and formatting as much as possible. Only provide the extracted text, nothing else.'
            }
          ]
        }],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 4096,
        }
      };

      final response = await _makeApiRequest('$_geminiEndpoint?key=$_geminiApiKey', requestBody);

      final data = jsonDecode(response.body);
      final extractedText = data['candidates'][0]['content']['parts'][0]['text'].trim();

      if (extractedText.isEmpty || extractedText.toLowerCase().contains('cannot extract') || extractedText.toLowerCase().contains('unable to')) {
        throw Exception('API could not extract text from PDF');
      }

      print('Successfully extracted text from PDF. Length: ${extractedText.length}');
      return extractedText;

    } catch (e) {
      print('PDF extraction error: $e');

      // Fallback: Try simple text-based extraction
      try {
        print('Attempting fallback PDF text extraction...');
        return await _fallbackPDFExtraction(pdfBytes);
      } catch (fallbackError) {
        print('Fallback PDF extraction also failed: $fallbackError');
        throw Exception('Failed to extract text from PDF: $e');
      }
    }
  }

  /// Fallback PDF text extraction method
  Future<String> _fallbackPDFExtraction(Uint8List pdfBytes) async {
    try {
      // Simple text extraction by looking for readable text patterns
      final text = utf8.decode(pdfBytes, allowMalformed: true);
      final lines = text.split('\n');
      final readableLines = <String>[];

      for (final line in lines) {
        final cleanLine = line.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ').trim();
        if (cleanLine.length > 10 && cleanLine.contains(' ')) {
          readableLines.add(cleanLine);
        }
      }

      final extractedText = readableLines.join('\n').trim();

      if (extractedText.length > 50) {
        print('Fallback extraction successful. Length: ${extractedText.length}');
        return extractedText;
      } else {
        throw Exception('Insufficient readable text found in PDF');
      }
    } catch (e) {
      throw Exception('Fallback PDF extraction failed: $e');
    }
  }

  /// Extract text from Word documents
  Future<String> _extractTextFromWord(Uint8List docBytes) async {
    print('Extracting text from Word document');

    // Check if file is too large
    if (docBytes.length > 5 * 1024 * 1024) {
      throw Exception('Word document too large (${getFileSizeString(docBytes.length)}). Maximum size: 5MB');
    }

    try {
      final base64Doc = base64Encode(docBytes);
      print('Word document encoded to base64, size: ${base64Doc.length} characters');

      final requestBody = {
        'contents': [{
          'parts': [
            {
              'inline_data': {
                'mime_type': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                'data': base64Doc,
              }
            },
            {
              'text': 'Extract all the text content from this Word document. Preserve the document structure and formatting as much as possible. Only provide the extracted text content, nothing else.'
            }
          ]
        }],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 4096,
        }
      };

      final response = await _makeApiRequest('$_geminiEndpoint?key=$_geminiApiKey', requestBody);

      final data = jsonDecode(response.body);
      final extractedText = data['candidates'][0]['content']['parts'][0]['text'].trim();

      if (extractedText.isNotEmpty && !extractedText.toLowerCase().contains('cannot') && !extractedText.toLowerCase().contains('unable')) {
        print('Successfully extracted text from Word document. Length: ${extractedText.length}');
        return extractedText;
      }

      // If API extraction failed, try fallback
      print('API extraction failed, trying fallback method');
      return await _fallbackWordExtraction(docBytes);

    } catch (e) {
      print('Word extraction error: $e');

      try {
        return await _fallbackWordExtraction(docBytes);
      } catch (fallbackError) {
        print('Fallback Word extraction also failed: $fallbackError');
        throw Exception('Failed to extract text from Word document: $e');
      }
    }
  }

  /// Fallback Word document text extraction
  Future<String> _fallbackWordExtraction(Uint8List docBytes) async {
    try {
      print('Attempting fallback Word text extraction...');

      final textContent = utf8.decode(docBytes, allowMalformed: true);
      final cleanedText = textContent
          .replaceAll(RegExp(r'[^\x20-\x7E\n\r\t]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (cleanedText.isNotEmpty && cleanedText.length > 50) {
        print('Fallback text extraction successful. Length: ${cleanedText.length}');
        return cleanedText;
      } else {
        throw Exception('Could not extract readable text from Word document');
      }
    } catch (e) {
      throw Exception('Fallback Word extraction failed: $e');
    }
  }

  /// Translate document content using Gemini
  Future<String> _translateDocumentContent(String content, String targetLanguage, String languageName) async {
    try {
      print('Translating content to $languageName. Content length: ${content.length}');

      // Truncate content if it's too long to avoid token limits
      String contentToTranslate = content;
      if (content.length > 8000) {
        contentToTranslate = content.substring(0, 8000) + '\n\n[Content truncated due to length...]';
        print('Content truncated to avoid token limits');
      }

      final requestBody = {
        'contents': [{
          'parts': [{
            'text': 'You are a professional document translator. Translate the following document content to $languageName.\n\nInstructions:\n- Maintain the document structure and formatting\n- Preserve technical terms appropriately\n- Keep the professional tone\n- Ensure cultural appropriateness\n- Only provide the translated content, nothing else\n\nDocument content to translate:\n$contentToTranslate\n\nTranslated document:'
          }]
        }],
        'generationConfig': {
          'temperature': 0.2,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 4096,
        }
      };

      final response = await _makeApiRequest('$_geminiEndpoint?key=$_geminiApiKey', requestBody);

      final data = jsonDecode(response.body);
      final translatedText = data['candidates'][0]['content']['parts'][0]['text'].trim();

      // Clean up the translation response
      String cleanedTranslation = _cleanTranslationResponse(translatedText);

      if (cleanedTranslation.isEmpty) {
        throw Exception('Translation returned empty content');
      }

      print('Translation successful. Translated length: ${cleanedTranslation.length}');
      return cleanedTranslation;

    } catch (e) {
      print('Translation error: $e');
      throw Exception('Failed to translate content: $e');
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
      'Translated document:',
      'Document translation:',
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

  /// Create a simple PDF with basic text formatting (avoids font issues)
  Future<Uint8List> _createSimpleTranslatedPDF({
    required String originalFileName,
    required String originalContent,
    required String translatedContent,
    required String targetLanguage,
  }) async {
    print('Creating simple PDF to avoid font issues');

    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    // Convert non-ASCII characters to ASCII equivalents for PDF
    final safeOriginal = _convertToSafeText(originalContent);
    final safeTranslated = _convertToSafeText(translatedContent);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Text(
              'Document Translation',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Original File: $originalFileName'),
            pw.Text('Translated to: $targetLanguage'),
            pw.Text('Translation Date: $formattedDate'),
            pw.SizedBox(height: 20),
            pw.Text(
              'Original Content',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text(safeOriginal),
            pw.SizedBox(height: 20),
            pw.Text(
              'Translated Content ($targetLanguage)',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text(safeTranslated),
            if (safeTranslated != translatedContent) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                'Note: Some characters were converted to ASCII equivalents for PDF compatibility.',
                style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
              ),
            ],
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Convert text to safe ASCII characters for PDF
  String _convertToSafeText(String text) {
    String safeText = text;

    // Replace common non-ASCII characters with ASCII equivalents
    final replacements = {
      // Chinese characters
      RegExp(r'[\u4e00-\u9fff]'): '[Chinese]',
      // Arabic characters
      RegExp(r'[\u0600-\u06ff]'): '[Arabic]',
      // Japanese characters
      RegExp(r'[\u3040-\u309f\u30a0-\u30ff]'): '[Japanese]',
      // Korean characters
      RegExp(r'[\uac00-\ud7af]'): '[Korean]',
      // Thai characters
      RegExp(r'[\u0e00-\u0e7f]'): '[Thai]',
      // Vietnamese characters
      RegExp(r'[àáảãạăắằẳẵặâấầẩẫậ]'): 'a',
      RegExp(r'[èéẻẽẹêếềểễệ]'): 'e',
      RegExp(r'[ìíỉĩị]'): 'i',
      RegExp(r'[òóỏõọôốồổỗộơớờởỡợ]'): 'o',
      RegExp(r'[ùúủũụưứừửữự]'): 'u',
      RegExp(r'[ỳýỷỹỵ]'): 'y',
      // Special Vietnamese characters
      RegExp(r'đ'): 'd',
      RegExp(r'Đ'): 'D',
    };

    for (final entry in replacements.entries) {
      safeText = safeText.replaceAll(entry.key, entry.value);
    }

    // Replace any remaining non-ASCII characters
    safeText = safeText.replaceAll(RegExp(r'[^\x00-\x7F]'), '?');

    return safeText;
  }

  /// Translate voice message with multimodal support
  Future<Map<String, String>?> translateVoiceMessage(String voicePath, String targetLanguage, String languageName) async {
    try {
      print('Translating voice message: $voicePath');

      // Read voice file
      final voiceBytes = await File(voicePath).readAsBytes();

      // Check file size
      if (voiceBytes.length > 5 * 1024 * 1024) {
        throw Exception('Audio file too large (${getFileSizeString(voiceBytes.length)}). Maximum size: 5MB');
      }

      final base64Audio = base64Encode(voiceBytes);
      final extension = voicePath.split('.').last.toLowerCase();
      final mimeType = getMimeType(extension);

      print('Voice file mime type: $mimeType, size: ${getFileSizeString(voiceBytes.length)}');

      final requestBody = {
        'contents': [{
          'parts': [
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Audio,
              }
            },
            {
              'text': 'You are an expert audio transcription and translation service.\n\nTask: Transcribe the audio content and translate it to $languageName.\n\nPlease provide the response in this exact format:\nORIGINAL: [transcribed text in original language]\nTRANSLATION: [translated text in $languageName]'
            }
          ]
        }],
        'generationConfig': {
          'temperature': 0.3,
          'maxOutputTokens': 1024,
        }
      };

      final response = await _makeApiRequest('$_geminiEndpoint?key=$_geminiApiKey', requestBody);

      final data = jsonDecode(response.body);
      final result = data['candidates'][0]['content']['parts'][0]['text'];

      return _parseVoiceTranslationResponse(result);

    } catch (e) {
      print('Voice translation error: $e');
      return null;
    }
  }

  /// Parse voice translation response
  Map<String, String>? _parseVoiceTranslationResponse(String response) {
    try {
      final lines = response.split('\n');
      String? original;
      String? translation;

      for (String line in lines) {
        final upperLine = line.toUpperCase();
        if (upperLine.startsWith('ORIGINAL:')) {
          original = line.substring(9).trim();
        } else if (upperLine.startsWith('TRANSLATION:')) {
          translation = line.substring(12).trim();
        }
      }

      if (original != null && translation != null) {
        return {
          'original': original,
          'translation': translation,
        };
      }

      // Fallback parsing
      if (response.contains('|')) {
        final parts = response.split('|');
        if (parts.length >= 2) {
          return {
            'original': parts[0].replaceAll(RegExp(r'ORIGINAL:?', caseSensitive: false), '').trim(),
            'translation': parts[1].replaceAll(RegExp(r'TRANSLATION:?', caseSensitive: false), '').trim(),
          };
        }
      }

      return null;
    } catch (e) {
      print('Error parsing voice translation response: $e');
      return null;
    }
  }

  /// Save file to device storage
  Future<File> saveFile(String base64Content, String fileName, String? directory) async {
    try {
      final bytes = base64Decode(base64Content);

      Directory targetDir;
      if (directory != null) {
        targetDir = Directory(directory);
      } else {
        targetDir = await getApplicationDocumentsDirectory();
      }

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final file = File('${targetDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      return file;
    } catch (e) {
      print('File save error: $e');
      throw Exception('Failed to save file: $e');
    }
  }

  /// Get file size in human readable format
  String getFileSizeString(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get file extension icon
  String getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return '📄';
      case 'doc':
      case 'docx':
        return '📝';
      case 'xls':
      case 'xlsx':
        return '📊';
      case 'ppt':
      case 'pptx':
        return '📋';
      case 'txt':
        return '📄';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return '🖼️';
      case 'mp3':
      case 'wav':
      case 'm4a':
        return '🎵';
      case 'mp4':
      case 'avi':
      case 'mov':
        return '🎬';
      default:
        return '📎';
    }
  }

  /// Create a simple PDF from text
  Future<Uint8List> createSimplePDF(String title, String content) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              _convertToSafeText(content),
              style: const pw.TextStyle(
                fontSize: 12,
                lineSpacing: 1.4,
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Check if file type is supported for translation
  bool isTranslationSupported(String extension) {
    final supportedTypes = ['txt', 'pdf', 'doc', 'docx'];
    return supportedTypes.contains(extension?.toLowerCase());
  }

  /// Get mime type for file extension
  String getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }
}