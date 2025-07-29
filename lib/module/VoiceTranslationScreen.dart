import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:translator/translator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';

class VoiceTranslationScreen extends StatefulWidget {
  final String? voiceFilePath;
  final Map<String, dynamic>? messageData;

  const VoiceTranslationScreen({
    Key? key,
    this.voiceFilePath,
    this.messageData,
  }) : super(key: key);

  @override
  _VoiceTranslationScreenState createState() => _VoiceTranslationScreenState();
}

class _VoiceTranslationScreenState extends State<VoiceTranslationScreen> {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final GoogleTranslator _translator = GoogleTranslator();

  String? recordedFilePath;
  String _recognizedText = '';
  String _translatedText = '';
  String _selectedLanguage = 'es'; // Default to Spanish
  bool _isListening = false;
  bool _isTranslating = false;
  bool _isSpeaking = false;

  // Common languages for translation
  final Map<String, String> _languages = {
    'Spanish': 'es',
    'French': 'fr',
    'German': 'de',
    'Italian': 'it',
    'Portuguese': 'pt',
    'Chinese': 'zh',
    'Japanese': 'ja',
    'Korean': 'ko',
    'Arabic': 'ar',
    'Russian': 'ru',
    'Hindi': 'hi',
  };

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
    _initializeTts();

    // If voice message data is provided, extract the file path
    if (widget.messageData != null) {
      _extractVoiceFile();
    } else if (widget.voiceFilePath != null) {
      recordedFilePath = widget.voiceFilePath;
    }
  }

  Future<void> _extractVoiceFile() async {
    if (widget.messageData != null && widget.messageData!['voiceBase64'] != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final fileName = widget.messageData!['voiceFileName'] ?? 'voice_message.wav';
        final voiceFile = File('${tempDir.path}/$fileName');
        await voiceFile.writeAsBytes(base64Decode(widget.messageData!['voiceBase64']));
        recordedFilePath = voiceFile.path;
      } catch (e) {
        print('Error extracting voice file: $e');
      }
    }
  }

  void _initializeSpeech() async {
    bool available = await _speechToText.initialize();
    if (!available) {
      print('Speech to text not available');
    }
  }

  void _initializeTts() async {
    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  // Main translation function
  Future<void> translateVoiceMessage(String audioFilePath) async {
    setState(() {
      _isTranslating = true;
      _recognizedText = '';
      _translatedText = '';
    });

    try {
      // Step 1: Convert voice to text
      await _convertVoiceToText(audioFilePath);

      if (_recognizedText.isNotEmpty) {
        // Step 2: Translate text
        await _translateText(_recognizedText);

        // Step 3: Speak translated text
        if (_translatedText.isNotEmpty) {
          await _speakTranslatedText();
        }
      }
    } catch (e) {
      _showErrorDialog('Translation Error', e.toString());
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  // Convert recorded audio file to text
  Future<void> _convertVoiceToText(String audioFilePath) async {
    try {
      // For recorded files, we need to use live listening as most packages
      // don't support direct audio file transcription
      bool available = await _speechToText.initialize();
      if (available) {
        setState(() {
          _isListening = true;
        });

        // Show dialog to ask user to play the recording and speak
        await _showPlayAndSpeakDialog();
      }
    } catch (e) {
      throw Exception('Failed to convert voice to text: $e');
    }
  }

  // Show dialog asking user to replay the audio and speak
  Future<void> _showPlayAndSpeakDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Voice Recognition'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please play your recording and speak clearly into the microphone.'),
              SizedBox(height: 20),
              _isListening
                  ? Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('Listening...'),
                ],
              )
                  : ElevatedButton(
                onPressed: _startListening,
                child: Text('Start Listening'),
              ),
              if (_recognizedText.isNotEmpty) ...[
                SizedBox(height: 10),
                Text('Recognized: $_recognizedText'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _stopListening,
              child: Text('Done'),
            ),
          ],
        );
      },
    );
  }

  // Start listening for speech
  void _startListening() async {
    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _recognizedText = result.recognizedWords;
        });
      },
      listenFor: Duration(seconds: 30),
      pauseFor: Duration(seconds: 3),
    );
    setState(() {
      _isListening = true;
    });
  }

  // Stop listening
  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
    Navigator.of(context).pop();
  }

  // Translate text to selected language
  Future<void> _translateText(String text) async {
    try {
      var translation = await _translator.translate(text, to: _selectedLanguage);
      setState(() {
        _translatedText = translation.text;
      });
    } catch (e) {
      throw Exception('Failed to translate text: $e');
    }
  }

  // Speak the translated text
  Future<void> _speakTranslatedText() async {
    if (_translatedText.isNotEmpty) {
      setState(() {
        _isSpeaking = true;
      });

      await _flutterTts.setLanguage(_selectedLanguage);
      await _flutterTts.speak(_translatedText);

      // Listen for completion
      _flutterTts.setCompletionHandler(() {
        setState(() {
          _isSpeaking = false;
        });
      });
    }
  }

  // Show error dialog
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Language selection dialog
  void _showLanguageSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Target Language'),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _languages.length,
            itemBuilder: (context, index) {
              String languageName = _languages.keys.elementAt(index);
              String languageCode = _languages[languageName]!;

              return ListTile(
                title: Text(languageName),
                trailing: _selectedLanguage == languageCode
                    ? Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedLanguage = languageCode;
                  });
                  _initializeTts(); // Reinitialize TTS with new language
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Voice Translator'),
        actions: [
          IconButton(
            icon: Icon(Icons.language),
            onPressed: _showLanguageSelector,
            tooltip: 'Select Language',
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Language selection
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.translate),
                    SizedBox(width: 10),
                    Text('Target Language: '),
                    Text(
                      _languages.keys.firstWhere(
                            (key) => _languages[key] == _selectedLanguage,
                        orElse: () => 'Unknown',
                      ),
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Spacer(),
                    ElevatedButton(
                      onPressed: _showLanguageSelector,
                      child: Text('Change'),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Original text display
            if (_recognizedText.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Original Text:', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(_recognizedText),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10),
            ],

            // Translated text display
            if (_translatedText.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Translated Text:', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(_translatedText),
                      SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _isSpeaking ? null : _speakTranslatedText,
                        icon: Icon(_isSpeaking ? Icons.volume_up : Icons.play_arrow),
                        label: Text(_isSpeaking ? 'Speaking...' : 'Play Translation'),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10),
            ],

            Spacer(),

            // Main translation button
            ElevatedButton.icon(
              onPressed: _isTranslating ? null : () {
                if (recordedFilePath != null) {
                  translateVoiceMessage(recordedFilePath!);
                } else {
                  _showErrorDialog('Error', 'No audio file available for translation');
                }
              },
              icon: _isTranslating
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Icon(Icons.translate),
              label: Text(_isTranslating ? 'Translating...' : 'Translate Voice'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _flutterTts.stop();
    super.dispose();
  }
}