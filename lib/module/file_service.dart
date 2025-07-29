import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class FileService {
  static const String _geminiApiKey = 'AIzaSyCFdlu9A8pY0FaZEMVaZ7eL-D9XcveMufo';
  static const String _geminiEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';

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

  /// Translate document and return as PDF
  Future<File?> translateDocument(PlatformFile file, String targetLanguage, String languageName) async {
    try {
      // Extract text from the document
      String content = await _extractTextFromFile(file);

      if (content.isEmpty) {
        throw Exception('Could not extract text from file');
      }

      // Translate the content
      String translatedContent = await _translateDocumentContent(content, targetLanguage, languageName);

      // Create PDF with translated content
      final pdf = await _createTranslatedPDF(
        originalFileName: file.name,
        originalContent: content,
        translatedContent: translatedContent,
        targetLanguage: languageName,
      );

      // Save PDF to temporary directory
      final directory = await getTemporaryDirectory();
      final pdfFile = File('${directory.path}/translated_${file.name.replaceAll(RegExp(r'\.[^.]*$'), '')}.pdf');
      await pdfFile.writeAsBytes(pdf);

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

  /// Extract text from PDF using Gemini Vision API
  Future<String> _extractTextFromPDF(Uint8List pdfBytes) async {
    try {
      final base64Pdf = base64Encode(pdfBytes);

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro-vision:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
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
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'].trim();
      } else {
        throw Exception('PDF text extraction failed: ${response.statusCode}');
      }
    } catch (e) {
      print('PDF extraction error: $e');
      throw Exception('Failed to extract text from PDF: $e');
    }
  }

  /// Extract text from Word documents using Gemini
  Future<String> _extractTextFromWord(Uint8List docBytes) async {
    try {
      final base64Doc = base64Encode(docBytes);

      final response = await http.post(
        Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': '''
This is a Word document in base64 format. Please extract all the text content from it.
Preserve the document structure and formatting as much as possible.
Only provide the extracted text content, nothing else.

Document data: $base64Doc'''
            }]
          }],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 4096,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'].trim();
      } else {
        throw Exception('Word document extraction failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Word extraction error: $e');
      // Fallback: try to read as plain text
      try {
        return utf8.decode(docBytes);
      } catch (_) {
        throw Exception('Failed to extract text from Word document: $e');
      }
    }
  }

  /// Translate document content using Gemini
  Future<String> _translateDocumentContent(String content, String targetLanguage, String languageName) async {
    try {
      final response = await http.post(
        Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': '''
You are a professional document translator. Translate the following document content to $languageName.

Instructions:
- Maintain the document structure and formatting
- Preserve technical terms appropriately 
- Keep the professional tone
- Ensure cultural appropriateness
- Only provide the translated content, nothing else

Document content to translate:
$content

Translated document:'''
            }]
          }],
          'generationConfig': {
            'temperature': 0.2,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 4096,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'].trim();
      } else {
        throw Exception('Translation failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Translation error: $e');
      throw Exception('Failed to translate content: $e');
    }
  }

  /// Create a professional PDF with translated content
  Future<Uint8List> _createTranslatedPDF({
    required String originalFileName,
    required String originalContent,
    required String translatedContent,
    required String targetLanguage,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    // Add pages to PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 20),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(width: 2, color: PdfColors.teal),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Document Translation',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Original File: $originalFileName',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    'Translated to: $targetLanguage',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    'Translation Date: $formattedDate',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Original Content Section
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Original Content',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    originalContent,
                    style: pw.TextStyle(
                      fontSize: 11,
                      color: PdfColors.grey700,
                      lineSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // Translated Content Section
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.teal50,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.teal200),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Translated Content ($targetLanguage)',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal800,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    translatedContent,
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.black,
                      lineSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 16),
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount} | Translated by AI Assistant',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey600,
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Translate voice message
  Future<Map<String, String>?> translateVoiceMessage(String voicePath, String targetLanguage, String languageName) async {
    try {
      // Read voice file
      final voiceBytes = await File(voicePath).readAsBytes();
      final base64Audio = base64Encode(voiceBytes);

      // Use Gemini to transcribe and translate
      final response = await http.post(
        Uri.parse('$_geminiEndpoint?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': '''
You are an expert audio transcription and translation service.

Task: Transcribe the audio content and translate it to $languageName.

Please provide the response in this exact format:
ORIGINAL: [transcribed text in original language]
TRANSLATION: [translated text in $languageName]

Audio data: $base64Audio'''
            }]
          }],
          'generationConfig': {
            'temperature': 0.3,
            'maxOutputTokens': 1024,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['candidates'][0]['content']['parts'][0]['text'];

        return _parseVoiceTranslationResponse(result);
      } else {
        throw Exception('Voice translation failed: ${response.statusCode}');
      }
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
              content,
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