import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:fyp/module/GroupCallService.dart';
import 'package:fyp/module/VoiceTranslationScreen.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import 'translation_service.dart';
import 'call_service.dart';
import 'file_service.dart';
import 'message_widgets.dart';

// =============================================================================
// CALL ICON WIDGETS
// =============================================================================

/// Private Chat Video Call Icon
class PrivateVideoCallIcon extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? iconColor;
  final double iconSize;
  final bool isEnabled;

  const PrivateVideoCallIcon({
    Key? key,
    required this.onPressed,
    this.iconColor,
    this.iconSize = 24.0,
    this.isEnabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.videocam,
        color: isEnabled ? (iconColor ?? Colors.white) : Colors.grey,
        size: iconSize,
      ),
      onPressed: isEnabled ? onPressed : null,
      tooltip: 'Private Video Call',
      splashRadius: 20,
    );
  }
}

/// Private Chat Voice Call Icon
class PrivateVoiceCallIcon extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? iconColor;
  final double iconSize;
  final bool isEnabled;

  const PrivateVoiceCallIcon({
    Key? key,
    required this.onPressed,
    this.iconColor,
    this.iconSize = 24.0,
    this.isEnabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.call,
        color: isEnabled ? (iconColor ?? Colors.white) : Colors.grey,
        size: iconSize,
      ),
      onPressed: isEnabled ? onPressed : null,
      tooltip: 'Private Voice Call',
      splashRadius: 20,
    );
  }
}

/// Group Chat Video Call Icon
class GroupVideoCallIcon extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? iconColor;
  final double iconSize;
  final bool isEnabled;

  const GroupVideoCallIcon({
    Key? key,
    required this.onPressed,
    this.iconColor,
    this.iconSize = 24.0,
    this.isEnabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Stack(
        children: [
          Icon(
            Icons.videocam,
            color: isEnabled ? (iconColor ?? Colors.white) : Colors.grey,
            size: iconSize,
          ),
          // Small group indicator
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isEnabled ? Colors.teal : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ],
      ),
      onPressed: isEnabled ? onPressed : null,
      tooltip: 'Group Video Call',
      splashRadius: 20,
    );
  }
}

/// Group Chat Voice Call Icon
class GroupVoiceCallIcon extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? iconColor;
  final double iconSize;
  final bool isEnabled;

  const GroupVoiceCallIcon({
    Key? key,
    required this.onPressed,
    this.iconColor,
    this.iconSize = 24.0,
    this.isEnabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Stack(
        children: [
          Icon(
            Icons.call,
            color: isEnabled ? (iconColor ?? Colors.white) : Colors.grey,
            size: iconSize,
          ),
          // Small group indicator
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isEnabled ? Colors.teal : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ],
      ),
      onPressed: isEnabled ? onPressed : null,
      tooltip: 'Group Voice Call',
      splashRadius: 20,
    );
  }
}

// =============================================================================
// CALL ICON BAR WIDGET
// =============================================================================

/// Widget that displays appropriate call icons based on chat type
class CallIconBar extends StatelessWidget {
  final bool isGroup;
  final bool canStartPrivateCall;
  final bool canStartGroupCall;
  final VoidCallback onPrivateVideoCall;
  final VoidCallback onPrivateVoiceCall;
  final VoidCallback onGroupVideoCall;
  final VoidCallback onGroupVoiceCall;

  const CallIconBar({
    Key? key,
    required this.isGroup,
    required this.canStartPrivateCall,
    required this.canStartGroupCall,
    required this.onPrivateVideoCall,
    required this.onPrivateVoiceCall,
    required this.onGroupVideoCall,
    required this.onGroupVoiceCall,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      // Show group call icons
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GroupVideoCallIcon(
            onPressed: onGroupVideoCall,
            isEnabled: canStartGroupCall,
          ),
          const SizedBox(width: 4),
          GroupVoiceCallIcon(
            onPressed: onGroupVoiceCall,
            isEnabled: canStartGroupCall,
          ),
        ],
      );
    } else {
      // Show private call icons
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrivateVideoCallIcon(
            onPressed: onPrivateVideoCall,
            isEnabled: canStartPrivateCall,
          ),
          const SizedBox(width: 4),
          PrivateVoiceCallIcon(
            onPressed: onPrivateVoiceCall,
            isEnabled: canStartPrivateCall,
          ),
        ],
      );
    }
  }
}

// =============================================================================
// MAIN CHAT MESSAGE CLASS
// =============================================================================

class ChatMessage extends StatefulWidget {
  final String currentUserCustomId;
  final String selectedCustomId;
  final String selectedUserName;
  final String selectedUserPhotoURL;

  const ChatMessage({
    Key? key,
    required this.currentUserCustomId,
    required this.selectedCustomId,
    required this.selectedUserName,
    required this.selectedUserPhotoURL,
  }) : super(key: key);

  @override
  _ChatMessageState createState() => _ChatMessageState();
}

class _ChatMessageState extends State<ChatMessage> {
  final TextEditingController _messageController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  // Services
  late TranslationService _translationService;
  late CallService _callService;
  GroupCallService? _groupCallService; // Added for group calls
  late FileService _fileService;

  // Language settings
  String _selectedLanguage = 'en';
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

  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isGroup = false;
  bool _isGroupOwner = false;
  bool _isInitialized = false; // Add initialization flag

  // Feature flags
  bool _isRealTimeTranslationEnabled = false;
  bool _showOriginalText = false;
  Map<String, String> _translationCache = {};
  Map<String, dynamic> _userPreferences = {};
  List<Map<String, dynamic>> _pinnedMessages = [];
  bool _isTyping = false;
  Timer? _typingTimer;
  String _currentTypingUser = '';
  String _currentUserName = '';
  String _currentUserPhotoURL = '';

  // Localized Interface
  Map<String, Map<String, String>> _localizedStrings = {
    'en': {
      'app_title': 'ChatHub',
      'your_chat_id': 'Your Chat ID',
      'create_new_group': 'Create New Group',
      'search_users': 'Search users by ID (e.g., ABC123)',
      'join_group': 'Join group by ID (e.g., ABC123)',
      'your_groups': 'Your Groups',
      'search_results': 'Search Results',
      'recent_chats': 'Recent Chats',
      'start_chat': 'Start Chat',
      'no_chats_yet': 'No chats yet',
      'search_or_join': 'Search users or join groups to start chatting',

      // Chat interface
      'type_message': 'Type a message...',
      'no_messages': 'No messages yet',
      'pinned_messages': 'Pinned Messages',
      'voice_message': 'Voice Message',
      'file': 'File',
      'image': 'Image',
      'sending': 'Sending...',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'typing': 'Typing...',
      'online': 'Online',
      'offline': 'Offline',
      'last_seen': 'Last seen',

      // Translation features
      'translate': 'Translate',
      'original': 'Original',
      'translation': 'Translation',
      'voice_translate': 'Voice Translation',
      'listening': 'Listening...',
      'speak_now': 'Speak now',
      'language_settings': 'Language Settings',
      'select_language': 'Select Language',
      'translation_settings': 'Translation Settings',
      'auto_translate': 'Auto-translate messages',
      'preferred_language': 'Preferred Language',
      'real_time_translation': 'Real-time Translation',
      'show_original_text': 'Show original text',
      'translate_current_message': 'Translate current message',
      'translation_successful': 'Translation successful!',
      'translation_failed': 'Translation failed',
      'please_type_message': 'Please type a message first',

      // File operations
      'document_options': 'Document Options',
      'send_original': 'Send original document',
      'translate_document': 'Translate document',
      'document_translated': 'Document translated and sent successfully!',
      'document_translation_error': 'Document translation error',
      'file_too_large': 'File size exceeds limit',
      'unsupported_file': 'Unsupported file format',
      'pick_file': 'Pick file',
      'take_photo': 'Take photo',
      'choose_gallery': 'Choose from gallery',
      'download': 'Download',
      'share': 'Share',
      'view_in_app': 'View in app',
      'save_to_device': 'Save to device',

      // Voice operations
      'voice_translation_options': 'Voice Translation Options',
      'send_voice': 'Send voice',
      'translate_first': 'Translate first',
      'send_as_text': 'Send as text',
      'voice_translation': 'Voice Translation',
      'transcription': 'Transcription',
      'voice_too_large': 'Voice message too large',
      'recording_failed': 'Recording failed',
      'voice_translation_failed': 'Voice translation failed',

      // Group management
      'group_members': 'Group Members',
      'modify_group': 'Modify group details',
      'delete_group': 'Delete group',
      'group_name': 'Group Name',
      'group_description': 'Group Description',
      'pick_image': 'Pick group image',
      'pin_message': 'Pin message',
      'unpin_message': 'Unpin message',
      'message_pinned': 'Message pinned',
      'message_unpinned': 'Message unpinned',

      // Common actions
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'close': 'Close',
      'copy_id': 'Copy ID',
      'share_id': 'Share ID',
      'ok': 'OK',
      'yes': 'Yes',
      'no': 'No',
      'error': 'Error',
      'success': 'Success',
      'loading': 'Loading...',
      'retry': 'Retry',
      'settings': 'Settings',

      // Error messages
      'permission_denied': 'Permission denied',
      'network_error': 'Network error',
      'file_not_found': 'File not found',
      'operation_failed': 'Operation failed',
      'unknown_error': 'An unknown error occurred',
    },
    'ar': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'معرف الدردشة الخاص بك',
      'create_new_group': 'إنشاء مجموعة جديدة',
      'search_users': 'البحث عن المستخدمين بالمعرف (مثال: ABC123)',
      'join_group': 'الانضمام للمجموعة بالمعرف (مثال: ABC123)',
      'your_groups': 'مجموعاتك',
      'search_results': 'نتائج البحث',
      'recent_chats': 'المحادثات الأخيرة',
      'start_chat': 'بدء محادثة',
      'no_chats_yet': 'لا توجد محادثات بعد',
      'search_or_join': 'ابحث عن المستخدمين أو انضم إلى المجموعات لبدء المحادثة',

      // Chat interface
      'type_message': 'اكتب رسالة...',
      'no_messages': 'لا توجد رسائل بعد',
      'pinned_messages': 'الرسائل المثبتة',
      'voice_message': 'رسالة صوتية',
      'file': 'ملف',
      'image': 'صورة',
      'sending': 'جارٍ الإرسال...',
      'today': 'اليوم',
      'yesterday': 'أمس',
      'typing': 'يكتب...',
      'online': 'متصل',
      'offline': 'غير متصل',
      'last_seen': 'آخر ظهور',

      // Translation features
      'translate': 'ترجمة',
      'original': 'الأصل',
      'translation': 'الترجمة',
      'voice_translate': 'الترجمة الصوتية',
      'listening': 'يستمع...',
      'speak_now': 'تحدث الآن',
      'language_settings': 'إعدادات اللغة',
      'select_language': 'اختر اللغة',
      'translation_settings': 'إعدادات الترجمة',
      'auto_translate': 'ترجمة الرسائل تلقائياً',
      'preferred_language': 'اللغة المفضلة',
      'real_time_translation': 'الترجمة الفورية',
      'show_original_text': 'إظهار النص الأصلي',
      'translate_current_message': 'ترجمة الرسالة الحالية',
      'translation_successful': 'نجحت الترجمة!',
      'translation_failed': 'فشلت الترجمة',
      'please_type_message': 'يرجى كتابة رسالة أولاً',

      // File operations
      'document_options': 'خيارات المستند',
      'send_original': 'إرسال المستند الأصلي',
      'translate_document': 'ترجمة المستند',
      'document_translated': 'تمت ترجمة المستند وإرساله بنجاح!',
      'document_translation_error': 'خطأ في ترجمة المستند',
      'file_too_large': 'حجم الملف يتجاوز الحد المسموح',
      'unsupported_file': 'تنسيق ملف غير مدعوم',
      'pick_file': 'اختر ملف',
      'take_photo': 'التقط صورة',
      'choose_gallery': 'اختر من المعرض',
      'download': 'تحميل',
      'share': 'مشاركة',
      'view_in_app': 'عرض في التطبيق',
      'save_to_device': 'حفظ على الجهاز',

      // Voice operations
      'voice_translation_options': 'خيارات الترجمة الصوتية',
      'send_voice': 'إرسال صوت',
      'translate_first': 'ترجم أولاً',
      'send_as_text': 'إرسال كنص',
      'voice_translation': 'الترجمة الصوتية',
      'transcription': 'النسخ',
      'voice_too_large': 'الرسالة الصوتية كبيرة جداً',
      'recording_failed': 'فشل في التسجيل',
      'voice_translation_failed': 'فشلت الترجمة الصوتية',

      // Group management
      'group_members': 'أعضاء المجموعة',
      'modify_group': 'تعديل تفاصيل المجموعة',
      'delete_group': 'حذف المجموعة',
      'group_name': 'اسم المجموعة',
      'group_description': 'وصف المجموعة',
      'pick_image': 'اختر صورة المجموعة',
      'pin_message': 'تثبيت الرسالة',
      'unpin_message': 'إلغاء تثبيت الرسالة',
      'message_pinned': 'تم تثبيت الرسالة',
      'message_unpinned': 'تم إلغاء تثبيت الرسالة',

      // Common actions
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'close': 'إغلاق',
      'copy_id': 'نسخ المعرف',
      'share_id': 'مشاركة المعرف',
      'ok': 'موافق',
      'yes': 'نعم',
      'no': 'لا',
      'error': 'خطأ',
      'success': 'نجح',
      'loading': 'جارٍ التحميل...',
      'retry': 'إعادة المحاولة',
      'settings': 'الإعدادات',

      // Error messages
      'permission_denied': 'تم رفض الإذن',
      'network_error': 'خطأ في الشبكة',
      'file_not_found': 'الملف غير موجود',
      'operation_failed': 'فشلت العملية',
      'unknown_error': 'حدث خطأ غير معروف',
    },

    'hi': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'आपकी चैट ID',
      'create_new_group': 'नया ग्रुप बनाएं',
      'search_users': 'ID से उपयोगकर्ता खोजें (जैसे: ABC123)',
      'join_group': 'ID से ग्रुप में शामिल हों (जैसे: ABC123)',
      'your_groups': 'आपके ग्रुप',
      'search_results': 'खोज परिणाम',
      'recent_chats': 'हाल की चैट',
      'start_chat': 'चैट शुरू करें',
      'no_chats_yet': 'अभी तक कोई चैट नहीं',
      'search_or_join': 'चैट शुरू करने के लिए उपयोगकर्ता खोजें या ग्रुप में शामिल हों',

      // Chat interface
      'type_message': 'संदेश लिखें...',
      'no_messages': 'अभी तक कोई संदेश नहीं',
      'pinned_messages': 'पिन किए गए संदेश',
      'voice_message': 'ध्वनि संदेश',
      'file': 'फ़ाइल',
      'image': 'चित्र',
      'sending': 'भेजा जा रहा है...',
      'today': 'आज',
      'yesterday': 'कल',
      'typing': 'टाइप कर रहा है...',
      'online': 'ऑनलाइन',
      'offline': 'ऑफलाइन',
      'last_seen': 'अंतिम बार देखा गया',

      // Translation features
      'translate': 'अनुवाद',
      'original': 'मूल',
      'translation': 'अनुवाद',
      'voice_translate': 'ध्वनि अनुवाद',
      'listening': 'सुन रहा है...',
      'speak_now': 'अब बोलें',
      'language_settings': 'भाषा सेटिंग',
      'select_language': 'भाषा चुनें',
      'translation_settings': 'अनुवाद सेटिंग',
      'auto_translate': 'संदेशों का स्वचालित अनुवाद',
      'preferred_language': 'पसंदीदा भाषा',
      'real_time_translation': 'वास्तविक समय अनुवाद',
      'show_original_text': 'मूल पाठ दिखाएं',
      'translate_current_message': 'वर्तमान संदेश का अनुवाद करें',
      'translation_successful': 'अनुवाद सफल!',
      'translation_failed': 'अनुवाद असफल',
      'please_type_message': 'कृपया पहले संदेश लिखें',

      // File operations
      'document_options': 'दस्तावेज़ विकल्प',
      'send_original': 'मूल दस्तावेज़ भेजें',
      'translate_document': 'दस्तावेज़ का अनुवाद करें',
      'document_translated': 'दस्तावेज़ का अनुवाद हो गया और सफलतापूर्वक भेजा गया!',
      'document_translation_error': 'दस्तावेज़ अनुवाद त्रुटि',
      'file_too_large': 'फ़ाइल का आकार सीमा से अधिक है',
      'unsupported_file': 'असमर्थित फ़ाइल प्रारूप',
      'pick_file': 'फ़ाइल चुनें',
      'take_photo': 'फोटो लें',
      'choose_gallery': 'गैलरी से चुनें',
      'download': 'डाउनलोड',
      'share': 'साझा करें',
      'view_in_app': 'ऐप में देखें',
      'save_to_device': 'डिवाइस में सहेजें',

      // Voice operations
      'voice_translation_options': 'ध्वनि अनुवाद विकल्प',
      'send_voice': 'ध्वनि भेजें',
      'translate_first': 'पहले अनुवाद करें',
      'send_as_text': 'पाठ के रूप में भेजें',
      'voice_translation': 'ध्वनि अनुवाद',
      'transcription': 'प्रतिलेखन',
      'voice_too_large': 'ध्वनि संदेश बहुत बड़ा है',
      'recording_failed': 'रिकॉर्डिंग असफल',
      'voice_translation_failed': 'ध्वनि अनुवाद असफल',

      // Group management
      'group_members': 'ग्रुप सदस्य',
      'modify_group': 'ग्रुप विवरण संशोधित करें',
      'delete_group': 'ग्रुप हटाएं',
      'group_name': 'ग्रुप का नाम',
      'group_description': 'ग्रुप विवरण',
      'pick_image': 'ग्रुप चित्र चुनें',
      'pin_message': 'संदेश पिन करें',
      'unpin_message': 'संदेश अनपिन करें',
      'message_pinned': 'संदेश पिन किया गया',
      'message_unpinned': 'संदेश अनपिन किया गया',

      // Common actions
      'save': 'सहेजें',
      'cancel': 'रद्द करें',
      'delete': 'हटाएं',
      'close': 'बंद करें',
      'copy_id': 'ID कॉपी करें',
      'share_id': 'ID साझा करें',
      'ok': 'ठीक',
      'yes': 'हां',
      'no': 'नहीं',
      'error': 'त्रुटि',
      'success': 'सफलता',
      'loading': 'लोड हो रहा है...',
      'retry': 'पुनः प्रयास',
      'settings': 'सेटिंग',

      // Error messages
      'permission_denied': 'अनुमति अस्वीकृत',
      'network_error': 'नेटवर्क त्रुटि',
      'file_not_found': 'फ़ाइल नहीं मिली',
      'operation_failed': 'ऑपरेशन असफल',
      'unknown_error': 'अज्ञात त्रुटि हुई',
    },
    'th': {
      'app_title': 'ChatHub',
      'your_chat_id': 'ID แชทของคุณ',
      'create_new_group': 'สร้างกลุ่มใหม่',
      'search_users': 'ค้นหาผู้ใช้ด้วย ID (เช่น: ABC123)',
      'join_group': 'เข้าร่วมกลุ่มด้วย ID (เช่น: ABC123)',
      'your_groups': 'กลุ่มของคุณ',
      'search_results': 'ผลการค้นหา',
      'recent_chats': 'แชทล่าสุด',
      'start_chat': 'เริ่มแชท',
      'no_chats_yet': 'ยังไม่มีแชท',
      'search_or_join': 'ค้นหาผู้ใช้หรือเข้าร่วมกลุ่มเพื่อเริ่มแชท',

      // Chat interface
      'type_message': 'พิมพ์ข้อความ...',
      'no_messages': 'ยังไม่มีข้อความ',
      'pinned_messages': 'ข้อความที่ปักหมุด',
      'voice_message': 'ข้อความเสียง',
      'file': 'ไฟล์',
      'image': 'รูปภาพ',
      'sending': 'กำลังส่ง...',
      'today': 'วันนี้',
      'yesterday': 'เมื่อวาน',
      'typing': 'กำลังพิมพ์...',
      'online': 'ออนไลน์',
      'offline': 'ออฟไลน์',
      'last_seen': 'เห็นครั้งสุดท้าย',

      // Translation features
      'translate': 'แปล',
      'original': 'ต้นฉบับ',
      'translation': 'การแปล',
      'voice_translate': 'การแปลเสียง',
      'listening': 'กำลังฟัง...',
      'speak_now': 'พูดเลย',
      'language_settings': 'การตั้งค่าภาษา',
      'select_language': 'เลือกภาษา',
      'translation_settings': 'การตั้งค่าการแปล',
      'auto_translate': 'แปลข้อความอัตโนมัติ',
      'preferred_language': 'ภาษาที่ต้องการ',
      'real_time_translation': 'การแปลแบบเรียลไทม์',
      'show_original_text': 'แสดงข้อความต้นฉบับ',
      'translate_current_message': 'แปลข้อความปัจจุบัน',
      'translation_successful': 'แปลสำเร็จ!',
      'translation_failed': 'การแปลล้มเหลว',
      'please_type_message': 'กรุณาพิมพ์ข้อความก่อน',

      // File operations
      'document_options': 'ตัวเลือกเอกสาร',
      'send_original': 'ส่งเอกสารต้นฉบับ',
      'translate_document': 'แปลเอกสาร',
      'document_translated': 'แปลเอกสารและส่งสำเร็จแล้ว!',
      'document_translation_error': 'ข้อผิดพลาดในการแปลเอกสาร',
      'file_too_large': 'ขนาดไฟล์เกินขีดจำกัด',
      'unsupported_file': 'รูปแบบไฟล์ที่ไม่รองรับ',
      'pick_file': 'เลือกไฟล์',
      'take_photo': 'ถ่ายภาพ',
      'choose_gallery': 'เลือกจากแกลเลอรี',
      'download': 'ดาวน์โหลด',
      'share': 'แชร์',
      'view_in_app': 'ดูในแอป',
      'save_to_device': 'บันทึกลงอุปกรณ์',

      // Voice operations
      'voice_translation_options': 'ตัวเลือกการแปลเสียง',
      'send_voice': 'ส่งเสียง',
      'translate_first': 'แปลก่อน',
      'send_as_text': 'ส่งเป็นข้อความ',
      'voice_translation': 'การแปลเสียง',
      'transcription': 'การถอดความ',
      'voice_too_large': 'ข้อความเสียงใหญ่เกินไป',
      'recording_failed': 'การบันทึกล้มเหลว',
      'voice_translation_failed': 'การแปลเสียงล้มเหลว',

      // Group management
      'group_members': 'สมาชิกกลุ่ม',
      'modify_group': 'แก้ไขรายละเอียดกลุ่ม',
      'delete_group': 'ลบกลุ่ม',
      'group_name': 'ชื่อกลุ่ม',
      'group_description': 'คำอธิบายกลุ่ม',
      'pick_image': 'เลือกรูปภาพกลุ่ม',
      'pin_message': 'ปักหมุดข้อความ',
      'unpin_message': 'ยกเลิกปักหมุดข้อความ',
      'message_pinned': 'ปักหมุดข้อความแล้ว',
      'message_unpinned': 'ยกเลิกปักหมุดข้อความแล้ว',

      // Common actions
      'save': 'บันทึก',
      'cancel': 'ยกเลิก',
      'delete': 'ลบ',
      'close': 'ปิด',
      'copy_id': 'คัดลอก ID',
      'share_id': 'แชร์ ID',
      'ok': 'ตกลง',
      'yes': 'ใช่',
      'no': 'ไม่',
      'error': 'ข้อผิดพลาด',
      'success': 'สำเร็จ',
      'loading': 'กำลังโหลด...',
      'retry': 'ลองใหม่',
      'settings': 'การตั้งค่า',

      // Error messages
      'permission_denied': 'ไม่อนุญาต',
      'network_error': 'ข้อผิดพลาดเครือข่าย',
      'file_not_found': 'ไม่พบไฟล์',
      'operation_failed': 'การดำเนินการล้มเหลว',
      'unknown_error': 'เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ',
    },
    'vi': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'ID Chat của bạn',
      'create_new_group': 'Tạo nhóm mới',
      'search_users': 'Tìm kiếm người dùng theo ID (ví dụ: ABC123)',
      'join_group': 'Tham gia nhóm theo ID (ví dụ: ABC123)',
      'your_groups': 'Nhóm của bạn',
      'search_results': 'Kết quả tìm kiếm',
      'recent_chats': 'Cuộc trò chuyện gần đây',
      'start_chat': 'Bắt đầu trò chuyện',
      'no_chats_yet': 'Chưa có cuộc trò chuyện nào',
      'search_or_join': 'Tìm kiếm người dùng hoặc tham gia nhóm để bắt đầu trò chuyện',

      // Chat interface
      'type_message': 'Nhập tin nhắn...',
      'no_messages': 'Chưa có tin nhắn nào',
      'pinned_messages': 'Tin nhắn đã ghim',
      'voice_message': 'Tin nhắn thoại',
      'file': 'Tệp tin',
      'image': 'Hình ảnh',
      'sending': 'Đang gửi...',
      'today': 'Hôm nay',
      'yesterday': 'Hôm qua',
      'typing': 'Đang nhập...',
      'online': 'Trực tuyến',
      'offline': 'Ngoại tuyến',
      'last_seen': 'Lần cuối truy cập',

      // Translation features
      'translate': 'Dịch',
      'original': 'Bản gốc',
      'translation': 'Bản dịch',
      'voice_translate': 'Dịch giọng nói',
      'listening': 'Đang nghe...',
      'speak_now': 'Nói ngay bây giờ',
      'language_settings': 'Cài đặt ngôn ngữ',
      'select_language': 'Chọn ngôn ngữ',
      'translation_settings': 'Cài đặt dịch thuật',
      'auto_translate': 'Tự động dịch tin nhắn',
      'preferred_language': 'Ngôn ngữ ưa thích',
      'real_time_translation': 'Dịch theo thời gian thực',
      'show_original_text': 'Hiển thị văn bản gốc',
      'translate_current_message': 'Dịch tin nhắn hiện tại',
      'translation_successful': 'Dịch thành công!',
      'translation_failed': 'Dịch thất bại',
      'please_type_message': 'Vui lòng nhập tin nhắn trước',

      // File operations
      'document_options': 'Tùy chọn tài liệu',
      'send_original': 'Gửi tài liệu gốc',
      'translate_document': 'Dịch tài liệu',
      'document_translated': 'Tài liệu đã được dịch và gửi thành công!',
      'document_translation_error': 'Lỗi dịch tài liệu',
      'file_too_large': 'Kích thước tệp vượt quá giới hạn',
      'unsupported_file': 'Định dạng tệp không được hỗ trợ',
      'pick_file': 'Chọn tệp',
      'take_photo': 'Chụp ảnh',
      'choose_gallery': 'Chọn từ thư viện',
      'download': 'Tải xuống',
      'share': 'Chia sẻ',
      'view_in_app': 'Xem trong ứng dụng',
      'save_to_device': 'Lưu vào thiết bị',

      // Voice operations
      'voice_translation_options': 'Tùy chọn dịch giọng nói',
      'send_voice': 'Gửi giọng nói',
      'translate_first': 'Dịch trước',
      'send_as_text': 'Gửi dưới dạng văn bản',
      'voice_translation': 'Dịch giọng nói',
      'transcription': 'Phiên âm',
      'voice_too_large': 'Tin nhắn thoại quá lớn',
      'recording_failed': 'Ghi âm thất bại',
      'voice_translation_failed': 'Dịch giọng nói thất bại',

      // Group management
      'group_members': 'Thành viên nhóm',
      'modify_group': 'Sửa đổi chi tiết nhóm',
      'delete_group': 'Xóa nhóm',
      'group_name': 'Tên nhóm',
      'group_description': 'Mô tả nhóm',
      'pick_image': 'Chọn hình ảnh nhóm',
      'pin_message': 'Ghim tin nhắn',
      'unpin_message': 'Bỏ ghim tin nhắn',
      'message_pinned': 'Đã ghim tin nhắn',
      'message_unpinned': 'Đã bỏ ghim tin nhắn',

      // Common actions
      'save': 'Lưu',
      'cancel': 'Hủy',
      'delete': 'Xóa',
      'close': 'Đóng',
      'copy_id': 'Sao chép ID',
      'share_id': 'Chia sẻ ID',
      'ok': 'OK',
      'yes': 'Có',
      'no': 'Không',
      'error': 'Lỗi',
      'success': 'Thành công',
      'loading': 'Đang tải...',
      'retry': 'Thử lại',
      'settings': 'Cài đặt',

      // Error messages
      'permission_denied': 'Quyền bị từ chối',
      'network_error': 'Lỗi mạng',
      'file_not_found': 'Không tìm thấy tệp',
      'operation_failed': 'Thao tác thất bại',
      'unknown_error': 'Đã xảy ra lỗi không xác định',
    },

    'id': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'ID Chat Anda',
      'create_new_group': 'Buat Grup Baru',
      'search_users': 'Cari pengguna berdasarkan ID (contoh: ABC123)',
      'join_group': 'Bergabung dengan grup berdasarkan ID (contoh: ABC123)',
      'your_groups': 'Grup Anda',
      'search_results': 'Hasil Pencarian',
      'recent_chats': 'Chat Terbaru',
      'start_chat': 'Mulai Chat',
      'no_chats_yet': 'Belum ada chat',
      'search_or_join': 'Cari pengguna atau bergabung dengan grup untuk mulai chatting',

      // Chat interface
      'type_message': 'Ketik pesan...',
      'no_messages': 'Belum ada pesan',
      'pinned_messages': 'Pesan yang Disematkan',
      'voice_message': 'Pesan Suara',
      'file': 'File',
      'image': 'Gambar',
      'sending': 'Mengirim...',
      'today': 'Hari ini',
      'yesterday': 'Kemarin',
      'typing': 'Sedang mengetik...',
      'online': 'Online',
      'offline': 'Offline',
      'last_seen': 'Terakhir dilihat',

      // Translation features
      'translate': 'Terjemahkan',
      'original': 'Asli',
      'translation': 'Terjemahan',
      'voice_translate': 'Terjemahan Suara',
      'listening': 'Mendengarkan...',
      'speak_now': 'Bicara sekarang',
      'language_settings': 'Pengaturan Bahasa',
      'select_language': 'Pilih Bahasa',
      'translation_settings': 'Pengaturan Terjemahan',
      'auto_translate': 'Terjemahkan pesan secara otomatis',
      'preferred_language': 'Bahasa Pilihan',
      'real_time_translation': 'Terjemahan Real-time',
      'show_original_text': 'Tampilkan teks asli',
      'translate_current_message': 'Terjemahkan pesan saat ini',
      'translation_successful': 'Terjemahan berhasil!',
      'translation_failed': 'Terjemahan gagal',
      'please_type_message': 'Silakan ketik pesan terlebih dahulu',

      // File operations
      'document_options': 'Opsi Dokumen',
      'send_original': 'Kirim dokumen asli',
      'translate_document': 'Terjemahkan dokumen',
      'document_translated': 'Dokumen berhasil diterjemahkan dan dikirim!',
      'document_translation_error': 'Kesalahan terjemahan dokumen',
      'file_too_large': 'Ukuran file melebihi batas',
      'unsupported_file': 'Format file tidak didukung',
      'pick_file': 'Pilih file',
      'take_photo': 'Ambil foto',
      'choose_gallery': 'Pilih dari galeri',
      'download': 'Unduh',
      'share': 'Bagikan',
      'view_in_app': 'Lihat di aplikasi',
      'save_to_device': 'Simpan ke perangkat',

      // Voice operations
      'voice_translation_options': 'Opsi Terjemahan Suara',
      'send_voice': 'Kirim suara',
      'translate_first': 'Terjemahkan dulu',
      'send_as_text': 'Kirim sebagai teks',
      'voice_translation': 'Terjemahan Suara',
      'transcription': 'Transkripsi',
      'voice_too_large': 'Pesan suara terlalu besar',
      'recording_failed': 'Perekaman gagal',
      'voice_translation_failed': 'Terjemahan suara gagal',

      // Group management
      'group_members': 'Anggota Grup',
      'modify_group': 'Ubah detail grup',
      'delete_group': 'Hapus grup',
      'group_name': 'Nama Grup',
      'group_description': 'Deskripsi Grup',
      'pick_image': 'Pilih gambar grup',
      'pin_message': 'Sematkan pesan',
      'unpin_message': 'Lepas sematan pesan',
      'message_pinned': 'Pesan disematkan',
      'message_unpinned': 'Pesan dilepas sematannya',

      // Common actions
      'save': 'Simpan',
      'cancel': 'Batal',
      'delete': 'Hapus',
      'close': 'Tutup',
      'copy_id': 'Salin ID',
      'share_id': 'Bagikan ID',
      'ok': 'OK',
      'yes': 'Ya',
      'no': 'Tidak',
      'error': 'Kesalahan',
      'success': 'Berhasil',
      'loading': 'Memuat...',
      'retry': 'Coba lagi',
      'settings': 'Pengaturan',

      // Error messages
      'permission_denied': 'Izin ditolak',
      'network_error': 'Kesalahan jaringan',
      'file_not_found': 'File tidak ditemukan',
      'operation_failed': 'Operasi gagal',
      'unknown_error': 'Terjadi kesalahan yang tidak diketahui',
    },
    'es': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'Tu ID de Chat',
      'create_new_group': 'Crear Nuevo Grupo',
      'search_users': 'Buscar usuarios por ID (ej: ABC123)',
      'join_group': 'Unirse al grupo por ID (ej: ABC123)',
      'your_groups': 'Tus Grupos',
      'search_results': 'Resultados de Búsqueda',
      'recent_chats': 'Chats Recientes',
      'start_chat': 'Iniciar Chat',
      'no_chats_yet': 'Aún no hay chats',
      'search_or_join': 'Busca usuarios o únete a grupos para empezar a chatear',

      // Chat interface
      'type_message': 'Escribe un mensaje...',
      'no_messages': 'Aún no hay mensajes',
      'pinned_messages': 'Mensajes Fijados',
      'voice_message': 'Mensaje de Voz',
      'file': 'Archivo',
      'image': 'Imagen',
      'sending': 'Enviando...',
      'today': 'Hoy',
      'yesterday': 'Ayer',
      'typing': 'Escribiendo...',
      'online': 'En línea',
      'offline': 'Desconectado',
      'last_seen': 'Última vez visto',

      // Translation features
      'translate': 'Traducir',
      'original': 'Original',
      'translation': 'Traducción',
      'voice_translate': 'Traducción de Voz',
      'listening': 'Escuchando...',
      'speak_now': 'Habla ahora',
      'language_settings': 'Configuración de Idioma',
      'select_language': 'Seleccionar Idioma',
      'translation_settings': 'Configuración de Traducción',
      'auto_translate': 'Traducir mensajes automáticamente',
      'preferred_language': 'Idioma Preferido',
      'real_time_translation': 'Traducción en Tiempo Real',
      'show_original_text': 'Mostrar texto original',
      'translate_current_message': 'Traducir mensaje actual',
      'translation_successful': '¡Traducción exitosa!',
      'translation_failed': 'Falló la traducción',
      'please_type_message': 'Por favor escribe un mensaje primero',

      // File operations
      'document_options': 'Opciones de Documento',
      'send_original': 'Enviar documento original',
      'translate_document': 'Traducir documento',
      'document_translated': '¡Documento traducido y enviado exitosamente!',
      'document_translation_error': 'Error en traducción del documento',
      'file_too_large': 'El archivo excede el límite de tamaño',
      'unsupported_file': 'Formato de archivo no soportado',
      'pick_file': 'Elegir archivo',
      'take_photo': 'Tomar foto',
      'choose_gallery': 'Elegir de la galería',
      'download': 'Descargar',
      'share': 'Compartir',
      'view_in_app': 'Ver en la app',
      'save_to_device': 'Guardar en dispositivo',

      // Voice operations
      'voice_translation_options': 'Opciones de Traducción de Voz',
      'send_voice': 'Enviar voz',
      'translate_first': 'Traducir primero',
      'send_as_text': 'Enviar como texto',
      'voice_translation': 'Traducción de Voz',
      'transcription': 'Transcripción',
      'voice_too_large': 'Mensaje de voz demasiado grande',
      'recording_failed': 'Falló la grabación',
      'voice_translation_failed': 'Falló la traducción de voz',

      // Group management
      'group_members': 'Miembros del Grupo',
      'modify_group': 'Modificar detalles del grupo',
      'delete_group': 'Eliminar grupo',
      'group_name': 'Nombre del Grupo',
      'group_description': 'Descripción del Grupo',
      'pick_image': 'Elegir imagen del grupo',
      'pin_message': 'Fijar mensaje',
      'unpin_message': 'Desfijar mensaje',
      'message_pinned': 'Mensaje fijado',
      'message_unpinned': 'Mensaje desfijado',

      // Common actions
      'save': 'Guardar',
      'cancel': 'Cancelar',
      'delete': 'Eliminar',
      'close': 'Cerrar',
      'copy_id': 'Copiar ID',
      'share_id': 'Compartir ID',
      'ok': 'OK',
      'yes': 'Sí',
      'no': 'No',
      'error': 'Error',
      'success': 'Éxito',
      'loading': 'Cargando...',
      'retry': 'Reintentar',
      'settings': 'Configuración',

      // Error messages
      'permission_denied': 'Permiso denegado',
      'network_error': 'Error de red',
      'file_not_found': 'Archivo no encontrado',
      'operation_failed': 'Operación fallida',
      'unknown_error': 'Ocurrió un error desconocido',
    },

    'fr': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'Votre ID de Chat',
      'create_new_group': 'Créer un Nouveau Groupe',
      'search_users': 'Rechercher des utilisateurs par ID (ex: ABC123)',
      'join_group': 'Rejoindre un groupe par ID (ex: ABC123)',
      'your_groups': 'Vos Groupes',
      'search_results': 'Résultats de Recherche',
      'recent_chats': 'Discussions Récentes',
      'start_chat': 'Commencer une Discussion',
      'no_chats_yet': 'Aucune discussion pour le moment',
      'search_or_join': 'Recherchez des utilisateurs ou rejoignez des groupes pour commencer à discuter',

      // Chat interface
      'type_message': 'Tapez un message...',
      'no_messages': 'Aucun message pour le moment',
      'pinned_messages': 'Messages Épinglés',
      'voice_message': 'Message Vocal',
      'file': 'Fichier',
      'image': 'Image',
      'sending': 'Envoi en cours...',
      'today': 'Aujourd\'hui',
      'yesterday': 'Hier',
      'typing': 'En train de taper...',
      'online': 'En ligne',
      'offline': 'Hors ligne',
      'last_seen': 'Vu pour la dernière fois',

      // Translation features
      'translate': 'Traduire',
      'original': 'Original',
      'translation': 'Traduction',
      'voice_translate': 'Traduction Vocale',
      'listening': 'Écoute en cours...',
      'speak_now': 'Parlez maintenant',
      'language_settings': 'Paramètres de Langue',
      'select_language': 'Sélectionner la Langue',
      'translation_settings': 'Paramètres de Traduction',
      'auto_translate': 'Traduire automatiquement les messages',
      'preferred_language': 'Langue Préférée',
      'real_time_translation': 'Traduction en Temps Réel',
      'show_original_text': 'Afficher le texte original',
      'translate_current_message': 'Traduire le message actuel',
      'translation_successful': 'Traduction réussie !',
      'translation_failed': 'Échec de la traduction',
      'please_type_message': 'Veuillez d\'abord taper un message',

      // File operations
      'document_options': 'Options de Document',
      'send_original': 'Envoyer le document original',
      'translate_document': 'Traduire le document',
      'document_translated': 'Document traduit et envoyé avec succès !',
      'document_translation_error': 'Erreur de traduction du document',
      'file_too_large': 'La taille du fichier dépasse la limite',
      'unsupported_file': 'Format de fichier non supporté',
      'pick_file': 'Choisir un fichier',
      'take_photo': 'Prendre une photo',
      'choose_gallery': 'Choisir dans la galerie',
      'download': 'Télécharger',
      'share': 'Partager',
      'view_in_app': 'Voir dans l\'app',
      'save_to_device': 'Enregistrer sur l\'appareil',

      // Voice operations
      'voice_translation_options': 'Options de Traduction Vocale',
      'send_voice': 'Envoyer la voix',
      'translate_first': 'Traduire d\'abord',
      'send_as_text': 'Envoyer comme texte',
      'voice_translation': 'Traduction Vocale',
      'transcription': 'Transcription',
      'voice_too_large': 'Message vocal trop volumineux',
      'recording_failed': 'Échec de l\'enregistrement',
      'voice_translation_failed': 'Échec de la traduction vocale',

      // Group management
      'group_members': 'Membres du Groupe',
      'modify_group': 'Modifier les détails du groupe',
      'delete_group': 'Supprimer le groupe',
      'group_name': 'Nom du Groupe',
      'group_description': 'Description du Groupe',
      'pick_image': 'Choisir l\'image du groupe',
      'pin_message': 'Épingler le message',
      'unpin_message': 'Désépingler le message',
      'message_pinned': 'Message épinglé',
      'message_unpinned': 'Message désépinglé',

      // Common actions
      'save': 'Enregistrer',
      'cancel': 'Annuler',
      'delete': 'Supprimer',
      'close': 'Fermer',
      'copy_id': 'Copier l\'ID',
      'share_id': 'Partager l\'ID',
      'ok': 'OK',
      'yes': 'Oui',
      'no': 'Non',
      'error': 'Erreur',
      'success': 'Succès',
      'loading': 'Chargement...',
      'retry': 'Réessayer',
      'settings': 'Paramètres',

      // Error messages
      'permission_denied': 'Permission refusée',
      'network_error': 'Erreur réseau',
      'file_not_found': 'Fichier non trouvé',
      'operation_failed': 'Opération échouée',
      'unknown_error': 'Une erreur inconnue s\'est produite',
    },
    'de': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'Ihre Chat-ID',
      'create_new_group': 'Neue Gruppe Erstellen',
      'search_users': 'Benutzer nach ID suchen (z.B.: ABC123)',
      'join_group': 'Gruppe per ID beitreten (z.B.: ABC123)',
      'your_groups': 'Ihre Gruppen',
      'search_results': 'Suchergebnisse',
      'recent_chats': 'Aktuelle Chats',
      'start_chat': 'Chat Starten',
      'no_chats_yet': 'Noch keine Chats',
      'search_or_join': 'Suchen Sie Benutzer oder treten Sie Gruppen bei, um zu chatten',

      // Chat interface
      'type_message': 'Nachricht eingeben...',
      'no_messages': 'Noch keine Nachrichten',
      'pinned_messages': 'Angeheftete Nachrichten',
      'voice_message': 'Sprachnachricht',
      'file': 'Datei',
      'image': 'Bild',
      'sending': 'Wird gesendet...',
      'today': 'Heute',
      'yesterday': 'Gestern',
      'typing': 'Tippt...',
      'online': 'Online',
      'offline': 'Offline',
      'last_seen': 'Zuletzt gesehen',

      // Translation features
      'translate': 'Übersetzen',
      'original': 'Original',
      'translation': 'Übersetzung',
      'voice_translate': 'Sprachübersetzung',
      'listening': 'Hört zu...',
      'speak_now': 'Jetzt sprechen',
      'language_settings': 'Spracheinstellungen',
      'select_language': 'Sprache Auswählen',
      'translation_settings': 'Übersetzungseinstellungen',
      'auto_translate': 'Nachrichten automatisch übersetzen',
      'preferred_language': 'Bevorzugte Sprache',
      'real_time_translation': 'Echtzeitübersetzung',
      'show_original_text': 'Originaltext anzeigen',
      'translate_current_message': 'Aktuelle Nachricht übersetzen',
      'translation_successful': 'Übersetzung erfolgreich!',
      'translation_failed': 'Übersetzung fehlgeschlagen',
      'please_type_message': 'Bitte geben Sie zuerst eine Nachricht ein',

      // File operations
      'document_options': 'Dokumentoptionen',
      'send_original': 'Originaldokument senden',
      'translate_document': 'Dokument übersetzen',
      'document_translated': 'Dokument erfolgreich übersetzt und gesendet!',
      'document_translation_error': 'Dokumentübersetzungsfehler',
      'file_too_large': 'Dateigröße überschreitet Limit',
      'unsupported_file': 'Nicht unterstütztes Dateiformat',
      'pick_file': 'Datei auswählen',
      'take_photo': 'Foto aufnehmen',
      'choose_gallery': 'Aus Galerie wählen',
      'download': 'Herunterladen',
      'share': 'Teilen',
      'view_in_app': 'In App anzeigen',
      'save_to_device': 'Auf Gerät speichern',

      // Voice operations
      'voice_translation_options': 'Sprachübersetzungsoptionen',
      'send_voice': 'Sprache senden',
      'translate_first': 'Zuerst übersetzen',
      'send_as_text': 'Als Text senden',
      'voice_translation': 'Sprachübersetzung',
      'transcription': 'Transkription',
      'voice_too_large': 'Sprachnachricht zu groß',
      'recording_failed': 'Aufnahme fehlgeschlagen',
      'voice_translation_failed': 'Sprachübersetzung fehlgeschlagen',

      // Group management
      'group_members': 'Gruppenmitglieder',
      'modify_group': 'Gruppendetails ändern',
      'delete_group': 'Gruppe löschen',
      'group_name': 'Gruppenname',
      'group_description': 'Gruppenbeschreibung',
      'pick_image': 'Gruppenbild auswählen',
      'pin_message': 'Nachricht anheften',
      'unpin_message': 'Nachricht lösen',
      'message_pinned': 'Nachricht angeheftet',
      'message_unpinned': 'Nachricht gelöst',

      // Common actions
      'save': 'Speichern',
      'cancel': 'Abbrechen',
      'delete': 'Löschen',
      'close': 'Schließen',
      'copy_id': 'ID kopieren',
      'share_id': 'ID teilen',
      'ok': 'OK',
      'yes': 'Ja',
      'no': 'Nein',
      'error': 'Fehler',
      'success': 'Erfolg',
      'loading': 'Wird geladen...',
      'retry': 'Wiederholen',
      'settings': 'Einstellungen',

      // Error messages
      'permission_denied': 'Berechtigung verweigert',
      'network_error': 'Netzwerkfehler',
      'file_not_found': 'Datei nicht gefunden',
      'operation_failed': 'Operation fehlgeschlagen',
      'unknown_error': 'Ein unbekannter Fehler ist aufgetreten',
    },

    'it': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'Il Tuo ID Chat',
      'create_new_group': 'Crea Nuovo Gruppo',
      'search_users': 'Cerca utenti per ID (es: ABC123)',
      'join_group': 'Unisciti al gruppo per ID (es: ABC123)',
      'your_groups': 'I Tuoi Gruppi',
      'search_results': 'Risultati di Ricerca',
      'recent_chats': 'Chat Recenti',
      'start_chat': 'Inizia Chat',
      'no_chats_yet': 'Nessuna chat ancora',
      'search_or_join': 'Cerca utenti o unisciti ai gruppi per iniziare a chattare',

      // Chat interface
      'type_message': 'Scrivi un messaggio...',
      'no_messages': 'Nessun messaggio ancora',
      'pinned_messages': 'Messaggi Fissati',
      'voice_message': 'Messaggio Vocale',
      'file': 'File',
      'image': 'Immagine',
      'sending': 'Invio in corso...',
      'today': 'Oggi',
      'yesterday': 'Ieri',
      'typing': 'Sta scrivendo...',
      'online': 'Online',
      'offline': 'Offline',
      'last_seen': 'Ultimo accesso',

      // Translation features
      'translate': 'Traduci',
      'original': 'Originale',
      'translation': 'Traduzione',
      'voice_translate': 'Traduzione Vocale',
      'listening': 'In ascolto...',
      'speak_now': 'Parla ora',
      'language_settings': 'Impostazioni Lingua',
      'select_language': 'Seleziona Lingua',
      'translation_settings': 'Impostazioni Traduzione',
      'auto_translate': 'Traduci automaticamente i messaggi',
      'preferred_language': 'Lingua Preferita',
      'real_time_translation': 'Traduzione in Tempo Reale',
      'show_original_text': 'Mostra testo originale',
      'translate_current_message': 'Traduci messaggio corrente',
      'translation_successful': 'Traduzione riuscita!',
      'translation_failed': 'Traduzione fallita',
      'please_type_message': 'Prima scrivi un messaggio',

      // File operations
      'document_options': 'Opzioni Documento',
      'send_original': 'Invia documento originale',
      'translate_document': 'Traduci documento',
      'document_translated': 'Documento tradotto e inviato con successo!',
      'document_translation_error': 'Errore traduzione documento',
      'file_too_large': 'File troppo grande',
      'unsupported_file': 'Formato file non supportato',
      'pick_file': 'Scegli file',
      'take_photo': 'Scatta foto',
      'choose_gallery': 'Scegli dalla galleria',
      'download': 'Scarica',
      'share': 'Condividi',
      'view_in_app': 'Visualizza nell\'app',
      'save_to_device': 'Salva sul dispositivo',

      // Voice operations
      'voice_translation_options': 'Opzioni Traduzione Vocale',
      'send_voice': 'Invia voce',
      'translate_first': 'Traduci prima',
      'send_as_text': 'Invia come testo',
      'voice_translation': 'Traduzione Vocale',
      'transcription': 'Trascrizione',
      'voice_too_large': 'Messaggio vocale troppo grande',
      'recording_failed': 'Registrazione fallita',
      'voice_translation_failed': 'Traduzione vocale fallita',

      // Group management
      'group_members': 'Membri del Gruppo',
      'modify_group': 'Modifica dettagli gruppo',
      'delete_group': 'Elimina gruppo',
      'group_name': 'Nome Gruppo',
      'group_description': 'Descrizione Gruppo',
      'pick_image': 'Scegli immagine gruppo',
      'pin_message': 'Fissa messaggio',
      'unpin_message': 'Rimuovi messaggio fissato',
      'message_pinned': 'Messaggio fissato',
      'message_unpinned': 'Messaggio rimosso',

      // Common actions
      'save': 'Salva',
      'cancel': 'Annulla',
      'delete': 'Elimina',
      'close': 'Chiudi',
      'copy_id': 'Copia ID',
      'share_id': 'Condividi ID',
      'ok': 'OK',
      'yes': 'Sì',
      'no': 'No',
      'error': 'Errore',
      'success': 'Successo',
      'loading': 'Caricamento...',
      'retry': 'Riprova',
      'settings': 'Impostazioni',

      // Error messages
      'permission_denied': 'Permesso negato',
      'network_error': 'Errore di rete',
      'file_not_found': 'File non trovato',
      'operation_failed': 'Operazione fallita',
      'unknown_error': 'Si è verificato un errore sconosciuto',
    },

    'pt': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'Seu ID de Chat',
      'create_new_group': 'Criar Novo Grupo',
      'search_users': 'Buscar usuários por ID (ex: ABC123)',
      'join_group': 'Entrar no grupo por ID (ex: ABC123)',
      'your_groups': 'Seus Grupos',
      'search_results': 'Resultados da Busca',
      'recent_chats': 'Conversas Recentes',
      'start_chat': 'Iniciar Conversa',
      'no_chats_yet': 'Ainda não há conversas',
      'search_or_join': 'Busque usuários ou entre em grupos para começar a conversar',

      // Chat interface
      'type_message': 'Digite uma mensagem...',
      'no_messages': 'Ainda não há mensagens',
      'pinned_messages': 'Mensagens Fixadas',
      'voice_message': 'Mensagem de Voz',
      'file': 'Arquivo',
      'image': 'Imagem',
      'sending': 'Enviando...',
      'today': 'Hoje',
      'yesterday': 'Ontem',
      'typing': 'Digitando...',
      'online': 'Online',
      'offline': 'Offline',
      'last_seen': 'Visto por último',

      // Translation features
      'translate': 'Traduzir',
      'original': 'Original',
      'translation': 'Tradução',
      'voice_translate': 'Tradução de Voz',
      'listening': 'Escutando...',
      'speak_now': 'Fale agora',
      'language_settings': 'Configurações de Idioma',
      'select_language': 'Selecionar Idioma',
      'translation_settings': 'Configurações de Tradução',
      'auto_translate': 'Traduzir mensagens automaticamente',
      'preferred_language': 'Idioma Preferido',
      'real_time_translation': 'Tradução em Tempo Real',
      'show_original_text': 'Mostrar texto original',
      'translate_current_message': 'Traduzir mensagem atual',
      'translation_successful': 'Tradução bem-sucedida!',
      'translation_failed': 'Tradução falhou',
      'please_type_message': 'Por favor, digite uma mensagem primeiro',

      // File operations
      'document_options': 'Opções de Documento',
      'send_original': 'Enviar documento original',
      'translate_document': 'Traduzir documento',
      'document_translated': 'Documento traduzido e enviado com sucesso!',
      'document_translation_error': 'Erro na tradução do documento',
      'file_too_large': 'Arquivo muito grande',
      'unsupported_file': 'Formato de arquivo não suportado',
      'pick_file': 'Escolher arquivo',
      'take_photo': 'Tirar foto',
      'choose_gallery': 'Escolher da galeria',
      'download': 'Baixar',
      'share': 'Compartilhar',
      'view_in_app': 'Ver no app',
      'save_to_device': 'Salvar no dispositivo',

      // Voice operations
      'voice_translation_options': 'Opções de Tradução de Voz',
      'send_voice': 'Enviar voz',
      'translate_first': 'Traduzir primeiro',
      'send_as_text': 'Enviar como texto',
      'voice_translation': 'Tradução de Voz',
      'transcription': 'Transcrição',
      'voice_too_large': 'Mensagem de voz muito grande',
      'recording_failed': 'Gravação falhou',
      'voice_translation_failed': 'Tradução de voz falhou',

      // Group management
      'group_members': 'Membros do Grupo',
      'modify_group': 'Modificar detalhes do grupo',
      'delete_group': 'Excluir grupo',
      'group_name': 'Nome do Grupo',
      'group_description': 'Descrição do Grupo',
      'pick_image': 'Escolher imagem do grupo',
      'pin_message': 'Fixar mensagem',
      'unpin_message': 'Desfixar mensagem',
      'message_pinned': 'Mensagem fixada',
      'message_unpinned': 'Mensagem desfixada',

      // Common actions
      'save': 'Salvar',
      'cancel': 'Cancelar',
      'delete': 'Excluir',
      'close': 'Fechar',
      'copy_id': 'Copiar ID',
      'share_id': 'Compartilhar ID',
      'ok': 'OK',
      'yes': 'Sim',
      'no': 'Não',
      'error': 'Erro',
      'success': 'Sucesso',
      'loading': 'Carregando...',
      'retry': 'Tentar novamente',
      'settings': 'Configurações',

      // Error messages
      'permission_denied': 'Permissão negada',
      'network_error': 'Erro de rede',
      'file_not_found': 'Arquivo não encontrado',
      'operation_failed': 'Operação falhou',
      'unknown_error': 'Ocorreu um erro desconhecido',
    },

    'ru': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'Ваш ID чата',
      'create_new_group': 'Создать новую группу',
      'search_users': 'Поиск пользователей по ID (например: ABC123)',
      'join_group': 'Присоединиться к группе по ID (например: ABC123)',
      'your_groups': 'Ваши группы',
      'search_results': 'Результаты поиска',
      'recent_chats': 'Недавние чаты',
      'start_chat': 'Начать чат',
      'no_chats_yet': 'Пока нет чатов',
      'search_or_join': 'Найдите пользователей или присоединитесь к группам для начала общения',

      // Chat interface
      'type_message': 'Введите сообщение...',
      'no_messages': 'Пока нет сообщений',
      'pinned_messages': 'Закрепленные сообщения',
      'voice_message': 'Голосовое сообщение',
      'file': 'Файл',
      'image': 'Изображение',
      'sending': 'Отправка...',
      'today': 'Сегодня',
      'yesterday': 'Вчера',
      'typing': 'Печатает...',
      'online': 'В сети',
      'offline': 'Не в сети',
      'last_seen': 'Был в сети',

      // Translation features
      'translate': 'Перевести',
      'original': 'Оригинал',
      'translation': 'Перевод',
      'voice_translate': 'Голосовой перевод',
      'listening': 'Слушаю...',
      'speak_now': 'Говорите сейчас',
      'language_settings': 'Настройки языка',
      'select_language': 'Выбрать язык',
      'translation_settings': 'Настройки перевода',
      'auto_translate': 'Автоматически переводить сообщения',
      'preferred_language': 'Предпочтительный язык',
      'real_time_translation': 'Перевод в реальном времени',
      'show_original_text': 'Показать оригинальный текст',
      'translate_current_message': 'Перевести текущее сообщение',
      'translation_successful': 'Перевод успешен!',
      'translation_failed': 'Перевод не удался',
      'please_type_message': 'Сначала введите сообщение',

      // File operations
      'document_options': 'Опции документа',
      'send_original': 'Отправить оригинальный документ',
      'translate_document': 'Перевести документ',
      'document_translated': 'Документ переведен и отправлен успешно!',
      'document_translation_error': 'Ошибка перевода документа',
      'file_too_large': 'Файл слишком большой',
      'unsupported_file': 'Неподдерживаемый формат файла',
      'pick_file': 'Выбрать файл',
      'take_photo': 'Сделать фото',
      'choose_gallery': 'Выбрать из галереи',
      'download': 'Скачать',
      'share': 'Поделиться',
      'view_in_app': 'Просмотреть в приложении',
      'save_to_device': 'Сохранить на устройство',

      // Voice operations
      'voice_translation_options': 'Опции голосового перевода',
      'send_voice': 'Отправить голос',
      'translate_first': 'Сначала перевести',
      'send_as_text': 'Отправить как текст',
      'voice_translation': 'Голосовой перевод',
      'transcription': 'Транскрипция',
      'voice_too_large': 'Голосовое сообщение слишком большое',
      'recording_failed': 'Запись не удалась',
      'voice_translation_failed': 'Голосовой перевод не удался',

      // Group management
      'group_members': 'Участники группы',
      'modify_group': 'Изменить детали группы',
      'delete_group': 'Удалить группу',
      'group_name': 'Название группы',
      'group_description': 'Описание группы',
      'pick_image': 'Выбрать изображение группы',
      'pin_message': 'Закрепить сообщение',
      'unpin_message': 'Открепить сообщение',
      'message_pinned': 'Сообщение закреплено',
      'message_unpinned': 'Сообщение откреплено',

      // Common actions
      'save': 'Сохранить',
      'cancel': 'Отмена',
      'delete': 'Удалить',
      'close': 'Закрыть',
      'copy_id': 'Копировать ID',
      'share_id': 'Поделиться ID',
      'ok': 'ОК',
      'yes': 'Да',
      'no': 'Нет',
      'error': 'Ошибка',
      'success': 'Успех',
      'loading': 'Загрузка...',
      'retry': 'Повторить',
      'settings': 'Настройки',

      // Error messages
      'permission_denied': 'Доступ запрещен',
      'network_error': 'Ошибка сети',
      'file_not_found': 'Файл не найден',
      'operation_failed': 'Операция не удалась',
      'unknown_error': 'Произошла неизвестная ошибка',
    },

    'ja': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': 'あなたのチャットID',
      'create_new_group': '新しいグループを作成',
      'search_users': 'IDでユーザーを検索 (例: ABC123)',
      'join_group': 'IDでグループに参加 (例: ABC123)',
      'your_groups': 'あなたのグループ',
      'search_results': '検索結果',
      'recent_chats': '最近のチャット',
      'start_chat': 'チャットを開始',
      'no_chats_yet': 'まだチャットがありません',
      'search_or_join': 'ユーザーを検索するかグループに参加してチャットを始めましょう',

      // Chat interface
      'type_message': 'メッセージを入力...',
      'no_messages': 'まだメッセージがありません',
      'pinned_messages': 'ピン留めされたメッセージ',
      'voice_message': 'ボイスメッセージ',
      'file': 'ファイル',
      'image': '画像',
      'sending': '送信中...',
      'today': '今日',
      'yesterday': '昨日',
      'typing': '入力中...',
      'online': 'オンライン',
      'offline': 'オフライン',
      'last_seen': '最後に表示',

      // Translation features
      'translate': '翻訳',
      'original': '原文',
      'translation': '翻訳',
      'voice_translate': '音声翻訳',
      'listening': '聞いています...',
      'speak_now': '今話してください',
      'language_settings': '言語設定',
      'select_language': '言語を選択',
      'translation_settings': '翻訳設定',
      'auto_translate': 'メッセージを自動翻訳',
      'preferred_language': '優先言語',
      'real_time_translation': 'リアルタイム翻訳',
      'show_original_text': '元のテキストを表示',
      'translate_current_message': '現在のメッセージを翻訳',
      'translation_successful': '翻訳が成功しました！',
      'translation_failed': '翻訳に失敗しました',
      'please_type_message': 'まずメッセージを入力してください',

      // File operations
      'document_options': 'ドキュメントオプション',
      'send_original': '元のドキュメントを送信',
      'translate_document': 'ドキュメントを翻訳',
      'document_translated': 'ドキュメントが翻訳され、正常に送信されました！',
      'document_translation_error': 'ドキュメント翻訳エラー',
      'file_too_large': 'ファイルサイズが制限を超えています',
      'unsupported_file': 'サポートされていないファイル形式',
      'pick_file': 'ファイルを選択',
      'take_photo': '写真を撮る',
      'choose_gallery': 'ギャラリーから選択',
      'download': 'ダウンロード',
      'share': '共有',
      'view_in_app': 'アプリで表示',
      'save_to_device': 'デバイスに保存',

      // Voice operations
      'voice_translation_options': '音声翻訳オプション',
      'send_voice': '音声を送信',
      'translate_first': 'まず翻訳',
      'send_as_text': 'テキストとして送信',
      'voice_translation': '音声翻訳',
      'transcription': '転写',
      'voice_too_large': 'ボイスメッセージが大きすぎます',
      'recording_failed': '録音に失敗しました',
      'voice_translation_failed': '音声翻訳に失敗しました',

      // Group management
      'group_members': 'グループメンバー',
      'modify_group': 'グループ詳細を変更',
      'delete_group': 'グループを削除',
      'group_name': 'グループ名',
      'group_description': 'グループの説明',
      'pick_image': 'グループ画像を選択',
      'pin_message': 'メッセージをピン留め',
      'unpin_message': 'ピン留めを解除',
      'message_pinned': 'メッセージがピン留めされました',
      'message_unpinned': 'メッセージのピン留めが解除されました',

      // Common actions
      'save': '保存',
      'cancel': 'キャンセル',
      'delete': '削除',
      'close': '閉じる',
      'copy_id': 'IDをコピー',
      'share_id': 'IDを共有',
      'ok': 'OK',
      'yes': 'はい',
      'no': 'いいえ',
      'error': 'エラー',
      'success': '成功',
      'loading': '読み込み中...',
      'retry': '再試行',
      'settings': '設定',

      // Error messages
      'permission_denied': '権限が拒否されました',
      'network_error': 'ネットワークエラー',
      'file_not_found': 'ファイルが見つかりません',
      'operation_failed': '操作に失敗しました',
      'unknown_error': '未知のエラーが発生しました',
    },

    'ko': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': '당신의 채팅 ID',
      'create_new_group': '새 그룹 만들기',
      'search_users': 'ID로 사용자 검색 (예: ABC123)',
      'join_group': 'ID로 그룹 참가 (예: ABC123)',
      'your_groups': '당신의 그룹',
      'search_results': '검색 결과',
      'recent_chats': '최근 채팅',
      'start_chat': '채팅 시작',
      'no_chats_yet': '아직 채팅이 없습니다',
      'search_or_join': '사용자를 검색하거나 그룹에 참가하여 채팅을 시작하세요',

      // Chat interface
      'type_message': '메시지를 입력하세요...',
      'no_messages': '아직 메시지가 없습니다',
      'pinned_messages': '고정된 메시지',
      'voice_message': '음성 메시지',
      'file': '파일',
      'image': '이미지',
      'sending': '전송 중...',
      'today': '오늘',
      'yesterday': '어제',
      'typing': '입력 중...',
      'online': '온라인',
      'offline': '오프라인',
      'last_seen': '마지막 접속',

      // Translation features
      'translate': '번역',
      'original': '원문',
      'translation': '번역',
      'voice_translate': '음성 번역',
      'listening': '듣고 있습니다...',
      'speak_now': '지금 말하세요',
      'language_settings': '언어 설정',
      'select_language': '언어 선택',
      'translation_settings': '번역 설정',
      'auto_translate': '메시지 자동 번역',
      'preferred_language': '선호 언어',
      'real_time_translation': '실시간 번역',
      'show_original_text': '원본 텍스트 표시',
      'translate_current_message': '현재 메시지 번역',
      'translation_successful': '번역 성공!',
      'translation_failed': '번역 실패',
      'please_type_message': '먼저 메시지를 입력하세요',

      // File operations
      'document_options': '문서 옵션',
      'send_original': '원본 문서 전송',
      'translate_document': '문서 번역',
      'document_translated': '문서가 번역되어 성공적으로 전송되었습니다!',
      'document_translation_error': '문서 번역 오류',
      'file_too_large': '파일 크기가 제한을 초과했습니다',
      'unsupported_file': '지원되지 않는 파일 형식',
      'pick_file': '파일 선택',
      'take_photo': '사진 촬영',
      'choose_gallery': '갤러리에서 선택',
      'download': '다운로드',
      'share': '공유',
      'view_in_app': '앱에서 보기',
      'save_to_device': '기기에 저장',

      // Voice operations
      'voice_translation_options': '음성 번역 옵션',
      'send_voice': '음성 전송',
      'translate_first': '먼저 번역',
      'send_as_text': '텍스트로 전송',
      'voice_translation': '음성 번역',
      'transcription': '전사',
      'voice_too_large': '음성 메시지가 너무 큽니다',
      'recording_failed': '녹음 실패',
      'voice_translation_failed': '음성 번역 실패',

      // Group management
      'group_members': '그룹 멤버',
      'modify_group': '그룹 세부정보 수정',
      'delete_group': '그룹 삭제',
      'group_name': '그룹 이름',
      'group_description': '그룹 설명',
      'pick_image': '그룹 이미지 선택',
      'pin_message': '메시지 고정',
      'unpin_message': '메시지 고정 해제',
      'message_pinned': '메시지가 고정되었습니다',
      'message_unpinned': '메시지 고정이 해제되었습니다',

      // Common actions
      'save': '저장',
      'cancel': '취소',
      'delete': '삭제',
      'close': '닫기',
      'copy_id': 'ID 복사',
      'share_id': 'ID 공유',
      'ok': '확인',
      'yes': '예',
      'no': '아니오',
      'error': '오류',
      'success': '성공',
      'loading': '로딩 중...',
      'retry': '다시 시도',
      'settings': '설정',

      // Error messages
      'permission_denied': '권한이 거부되었습니다',
      'network_error': '네트워크 오류',
      'file_not_found': '파일을 찾을 수 없습니다',
      'operation_failed': '작업이 실패했습니다',
      'unknown_error': '알 수 없는 오류가 발생했습니다',
    },

    'zh': {
      // App basics
      'app_title': 'ChatHub',
      'your_chat_id': '您的聊天ID',
      'create_new_group': '创建新群组',
      'search_users': '通过ID搜索用户 (例如: ABC123)',
      'join_group': '通过ID加入群组 (例如: ABC123)',
      'your_groups': '您的群组',
      'search_results': '搜索结果',
      'recent_chats': '最近聊天',
      'start_chat': '开始聊天',
      'no_chats_yet': '暂无聊天',
      'search_or_join': '搜索用户或加入群组开始聊天',

      // Chat interface
      'type_message': '输入消息...',
      'no_messages': '暂无消息',
      'pinned_messages': '置顶消息',
      'voice_message': '语音消息',
      'file': '文件',
      'image': '图片',
      'sending': '发送中...',
      'today': '今天',
      'yesterday': '昨天',
      'typing': '正在输入...',
      'online': '在线',
      'offline': '离线',
      'last_seen': '最后在线',

      // Translation features
      'translate': '翻译',
      'original': '原文',
      'translation': '翻译',
      'voice_translate': '语音翻译',
      'listening': '正在听...',
      'speak_now': '现在说话',
      'language_settings': '语言设置',
      'select_language': '选择语言',
      'translation_settings': '翻译设置',
      'auto_translate': '自动翻译消息',
      'preferred_language': '首选语言',
      'real_time_translation': '实时翻译',
      'show_original_text': '显示原文',
      'translate_current_message': '翻译当前消息',
      'translation_successful': '翻译成功！',
      'translation_failed': '翻译失败',
      'please_type_message': '请先输入消息',

      // File operations
      'document_options': '文档选项',
      'send_original': '发送原文档',
      'translate_document': '翻译文档',
      'document_translated': '文档翻译并发送成功！',
      'document_translation_error': '文档翻译错误',
      'file_too_large': '文件大小超出限制',
      'unsupported_file': '不支持的文件格式',
      'pick_file': '选择文件',
      'take_photo': '拍照',
      'choose_gallery': '从相册选择',
      'download': '下载',
      'share': '分享',
      'view_in_app': '在应用中查看',
      'save_to_device': '保存到设备',

      // Voice operations
      'voice_translation_options': '语音翻译选项',
      'send_voice': '发送语音',
      'translate_first': '先翻译',
      'send_as_text': '作为文本发送',
      'voice_translation': '语音翻译',
      'transcription': '转录',
      'voice_too_large': '语音消息过大',
      'recording_failed': '录音失败',
      'voice_translation_failed': '语音翻译失败',

      // Group management
      'group_members': '群组成员',
      'modify_group': '修改群组详情',
      'delete_group': '删除群组',
      'group_name': '群组名称',
      'group_description': '群组描述',
      'pick_image': '选择群组图片',
      'pin_message': '置顶消息',
      'unpin_message': '取消置顶',
      'message_pinned': '消息已置顶',
      'message_unpinned': '消息已取消置顶',

      // Common actions
      'save': '保存',
      'cancel': '取消',
      'delete': '删除',
      'close': '关闭',
      'copy_id': '复制ID',
      'share_id': '分享ID',
      'ok': '确定',
      'yes': '是',
      'no': '否',
      'error': '错误',
      'success': '成功',
      'loading': '加载中...',
      'retry': '重试',
      'settings': '设置',

      // Error messages
      'permission_denied': '权限被拒绝',
      'network_error': '网络错误',
      'file_not_found': '文件未找到',
      'operation_failed': '操作失败',
      'unknown_error': '发生未知错误',
    },
  };

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadUserPreferences();
    _setupTypingIndicator();
    _resetUnreadMessages();
    _initializeChat(); // New method to handle async initialization
  }

  // New method to handle async initialization
  Future<void> _initializeChat() async {
    try {
      await _loadCurrentUserInfo();
      await _checkIfGroup();
      await _checkIfGroupOwner(); // Make sure this completes

      // Initialize group call service after all data is loaded
      if (_isGroup && _currentUserName.isNotEmpty) {
        _initializeGroupCallService();
      }

      setState(() {
        _isInitialized = true;
      });

      print('Chat initialization complete - isGroup: $_isGroup, isGroupOwner: $_isGroupOwner');

    } catch (e) {
      print('Error initializing chat: $e');
      setState(() {
        _isInitialized = true; // Still set to true to avoid infinite loading
      });
    }
  }

  void _initializeServices() {
    _translationService = TranslationService();
    _callService = CallService(
      context: context,
      currentUserCustomId: widget.currentUserCustomId,
      selectedCustomId: widget.selectedCustomId,
      selectedUserName: widget.selectedUserName,
      selectedUserPhotoURL: widget.selectedUserPhotoURL,
      onCallEnded: () {
        // Called when user chooses to go back to chat after call ends
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
    );
    _fileService = FileService();
    _callService.initialize();
  }

  Future<void> _loadCurrentUserInfo() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('profiledetails')
            .doc('profile')
            .get();

        if (userDoc.exists) {
          setState(() {
            _currentUserName = userDoc['name'] ?? 'Unknown';
            _currentUserPhotoURL = userDoc['photoURL'] ?? '';
          });
          print('Current user loaded: $_currentUserName');
        }
      }
    } catch (e) {
      print('Error loading current user info: $e');
    }
  }

  void _initializeGroupCallService() {
    if (_isGroup) {
      _groupCallService = GroupCallService(
        context: context,
        currentUserCustomId: widget.currentUserCustomId,
        currentUserName: _currentUserName,
        currentUserPhotoURL: _currentUserPhotoURL,
        groupId: widget.selectedCustomId,
        groupName: widget.selectedUserName,
        onCallEnded: () {
          // Handle call ended
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      );
      _groupCallService!.initialize();
    }
  }

  // Fixed group checking method
  Future<void> _checkIfGroup() async {
    try {
      print('Checking if group for ID: ${widget.selectedCustomId}');
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.selectedCustomId)
          .get();

      final isGroup = groupDoc.exists;
      print('Is group chat: $isGroup');

      setState(() {
        _isGroup = isGroup;
      });
    } catch (e) {
      print('Error checking if group: $e');
      setState(() {
        _isGroup = false;
      });
    }
  }

  // Fixed group owner checking method
  Future<void> _checkIfGroupOwner() async {
    if (!_isGroup) {
      setState(() {
        _isGroupOwner = false;
      });
      return;
    }

    try {
      print('Checking if user is group owner for group: ${widget.selectedCustomId}');

      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.selectedCustomId)
          .get();

      if (!groupDoc.exists) {
        print('Group document does not exist');
        setState(() {
          _isGroupOwner = false;
        });
        return;
      }

      final groupData = groupDoc.data() as Map<String, dynamic>;
      final creatorId = groupData['creatorId'];
      print('Group creator ID: $creatorId');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('Current user is null');
        setState(() {
          _isGroupOwner = false;
        });
        return;
      }

      print('Current user UID: ${currentUser.uid}');
      print('Current user custom ID: ${widget.currentUserCustomId}');

      // Check if current user is the creator
      bool isOwner = creatorId == currentUser.uid;

      print('Is group owner: $isOwner');

      setState(() {
        _isGroupOwner = isOwner;
      });

    } catch (e) {
      print('Error checking group owner status: $e');
      setState(() {
        _isGroupOwner = false;
      });
    }
  }

  // =============================================================================
  // CALL FUNCTIONS
  // =============================================================================

  /// Start private video call
  Future<void> startPrivateVideoCall() async {
    try {
      print('Starting private video call...');

      if (_isGroup) {
        _showError('Cannot start private call in group chat');
        return;
      }

      await _callService.startVideoCall();
    } catch (e) {
      print('Error starting private video call: $e');
      _showError('Failed to start video call: $e');
    }
  }

  /// Start private voice call
  Future<void> startPrivateVoiceCall() async {
    try {
      print('Starting private voice call...');

      if (_isGroup) {
        _showError('Cannot start private call in group chat');
        return;
      }

      await _callService.startVoiceCall();
    } catch (e) {
      print('Error starting private voice call: $e');
      _showError('Failed to start voice call: $e');
    }
  }

  /// Start group video call
  Future<void> startGroupVideoCall() async {
    try {
      print('Starting group video call...');

      if (!_isGroup) {
        _showError('Group calls only available in group chats');
        return;
      }

      if (_groupCallService == null) {
        _showError('Group call service not available');
        return;
      }

      if (_groupCallService!.isInCall) {
        _showError('Already in a call');
        return;
      }

      await _groupCallService!.startGroupVideoCall();
    } catch (e) {
      print('Error starting group video call: $e');
      _showError('Failed to start group video call: $e');
    }
  }

  /// Start group voice call
  Future<void> startGroupVoiceCall() async {
    try {
      print('Starting group voice call...');

      if (!_isGroup) {
        _showError('Group calls only available in group chats');
        return;
      }

      if (_groupCallService == null) {
        _showError('Group call service not available');
        return;
      }

      if (_groupCallService!.isInCall) {
        _showError('Already in a call');
        return;
      }

      await _groupCallService!.startGroupVoiceCall();
    } catch (e) {
      print('Error starting group voice call: $e');
      _showError('Failed to start group voice call: $e');
    }
  }

  /// Check if group calls are available
  bool canStartGroupCall() {
    return _isGroup &&
        _groupCallService != null &&
        _groupCallService!.canStartCall();
  }

  /// Check if private calls are available
  bool canStartPrivateCall() {
    return !_isGroup; // Removed the isInCall check since CallService doesn't have it
  }

  // Reset unread messages when opening chat
  Future<void> _resetUnreadMessages() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('unread_counts')
          .doc('counts')
          .update({widget.selectedCustomId: FieldValue.delete()});
    } catch (e) {
      print('Error resetting unread count: $e');
    }
  }

  // Get localized string
  String _getLocalizedString(String key) {
    return _localizedStrings[_selectedLanguage]?[key] ??
        _localizedStrings['en']?[key] ??
        key;
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isRealTimeTranslationEnabled = prefs.getBool('realTimeTranslation_${widget.currentUserCustomId}') ?? false;
      _selectedLanguage = prefs.getString('preferredLanguage_${widget.currentUserCustomId}') ?? 'en';
      _showOriginalText = prefs.getBool('showOriginalText_${widget.currentUserCustomId}') ?? false;
    });
  }

  Future<void> _saveUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('realTimeTranslation_${widget.currentUserCustomId}', _isRealTimeTranslationEnabled);
    await prefs.setString('preferredLanguage_${widget.currentUserCustomId}', _selectedLanguage);
    await prefs.setBool('showOriginalText_${widget.currentUserCustomId}', _showOriginalText);
  }

  void _setupTypingIndicator() {
    _messageController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_messageController.text.isNotEmpty && !_isTyping) {
      _sendTypingIndicator(true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _sendTypingIndicator(false);
      });
    } else if (_messageController.text.isEmpty && _isTyping) {
      _sendTypingIndicator(false);
      _typingTimer?.cancel();
    }
  }

  Future<void> _sendTypingIndicator(bool isTyping) async {
    setState(() {
      _isTyping = isTyping;
    });

    try {
      final typingData = {
        'userCustomId': widget.currentUserCustomId,
        'userName': widget.selectedUserName,
        'isTyping': isTyping,
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (_isGroup) {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('typing')
            .doc(widget.currentUserCustomId)
            .set(typingData);
      } else {
        final chatRoomId = _getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId);
        await FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(chatRoomId)
            .collection('typing')
            .doc(widget.currentUserCustomId)
            .set(typingData);
      }

      if (isTyping) {
        Future.delayed(const Duration(seconds: 5), () {
          _sendTypingIndicator(false);
        });
      }
    } catch (e) {
      print('Error sending typing indicator: $e');
    }
  }

  // Show all pinned messages from app bar
  void _showAllPinnedMessages() {
    if (!_isGroup) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.push_pin, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Pinned Messages',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[700],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.selectedCustomId)
                    .collection('pinned_messages')
                    .orderBy('pinnedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.push_pin_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No pinned messages',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final pinnedMessage = snapshot.data!.docs[index];
                      final data = pinnedMessage.data() as Map<String, dynamic>;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    data['senderName'] ?? 'Unknown',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal[800],
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_isGroupOwner)
                                    IconButton(
                                      onPressed: () async {
                                        // Unpin this message
                                        try {
                                          await FirebaseFirestore.instance
                                              .collection('groups')
                                              .doc(widget.selectedCustomId)
                                              .collection('messages')
                                              .doc(data['messageId'])
                                              .update({'isPinned': false});

                                          await FirebaseFirestore.instance
                                              .collection('groups')
                                              .doc(widget.selectedCustomId)
                                              .collection('pinned_messages')
                                              .doc(data['messageId'])
                                              .delete();
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to unpin: $e'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                      icon: Icon(
                                        Icons.push_pin_outlined,
                                        color: Colors.amber[700],
                                        size: 20,
                                      ),
                                      tooltip: 'Unpin message',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                data['text'] ?? 'Media message',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Pinned ${data['pinnedAt'] != null
                                    ? DateFormat('MMM dd, yyyy HH:mm').format(
                                    (data['pinnedAt'] as Timestamp).toDate())
                                    : 'recently'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Language Settings Dialog
  void _showLanguageSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.language, color: Colors.teal[800]),
              const SizedBox(width: 8),
              const Text('Language Settings'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Real-time Translation'),
                  subtitle: const Text('Automatically translate incoming messages'),
                  value: _isRealTimeTranslationEnabled,
                  onChanged: (bool value) {
                    setDialogState(() {
                      _isRealTimeTranslationEnabled = value;
                    });
                    setState(() {
                      _isRealTimeTranslationEnabled = value;
                    });
                    _saveUserPreferences();
                  },
                  activeColor: Colors.teal[800],
                ),
                const Divider(),

                SwitchListTile(
                  title: const Text('Show Original Text'),
                  subtitle: const Text('Display original text along with translation'),
                  value: _showOriginalText,
                  onChanged: (bool value) {
                    setDialogState(() {
                      _showOriginalText = value;
                    });
                    setState(() {
                      _showOriginalText = value;
                    });
                    _saveUserPreferences();
                  },
                  activeColor: Colors.teal[800],
                ),
                const Divider(),

                const Text(
                  'Preferred Language',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.teal),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLanguage,
                      isExpanded: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      items: _languageNames.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Row(
                            children: [
                              Text(
                                _getLanguageFlag(entry.key),
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Text(entry.value),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setDialogState(() {
                            _selectedLanguage = newValue;
                          });
                          setState(() {
                            _selectedLanguage = newValue;
                          });
                          _saveUserPreferences();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  onPressed: () async {
                    final text = _messageController.text;
                    if (text.isNotEmpty) {
                      try {
                        final translated = await _translationService.translateText(text, _selectedLanguage);
                        _messageController.text = translated;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Message translated successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Translation failed: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please type a message first'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.translate),
                  label: const Text('Translate Current Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String _getLanguageFlag(String langCode) {
    final flags = {
      'en': '🇬🇧',
      'ar': '🇸🇦',
      'hi': '🇮🇳',
      'th': '🇹🇭',
      'vi': '🇻🇳',
      'id': '🇮🇩',
      'es': '🇪🇸',
      'fr': '🇫🇷',
      'de': '🇩🇪',
      'it': '🇮🇹',
      'pt': '🇵🇹',
      'ru': '🇷🇺',
      'ja': '🇯🇵',
      'ko': '🇰🇷',
      'zh': '🇨🇳',



    };
    return flags[langCode] ?? '🌐';
  }

  // Image picker with compression
  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        final file = File(image.path);
        final fileBytes = await file.readAsBytes();

        if (fileBytes.length > 5 * 1024 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image size exceeds 5MB limit'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final base64Image = base64Encode(fileBytes);
        await _sendMessage(
          imageBase64: base64Image,
          imageName: path.basename(image.path),
          messageType: 'image',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // File picker with document translation option
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'],
      );

      if (result != null) {
        final file = result.files.first;
        final extension = file.extension?.toLowerCase() ?? '';

        if (['txt', 'pdf', 'doc', 'docx'].contains(extension)) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Document Options'),
              content: const Text('Would you like to translate this document?'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _sendFileMessage(file);
                  },
                  child: const Text('Send Original'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _translateDocument(file);
                  },
                  child: const Text('Translate'),
                ),
              ],
            ),
          );
        } else {
          _sendFileMessage(file);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _translateDocument(PlatformFile file) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final translatedPdf = await _fileService.translateDocument(
          file,
          _selectedLanguage,
          _languageNames[_selectedLanguage] ?? 'English'
      );

      Navigator.pop(context);

      if (translatedPdf != null) {
        final base64Pdf = base64Encode(await translatedPdf.readAsBytes());
        await _sendMessage(
          fileBase64: base64Pdf,
          fileName: 'translated_${file.name.replaceAll(RegExp(r'\.[^.]*$'), '')}.pdf',
          messageType: 'file',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document translated and sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document translation error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendFileMessage(PlatformFile file) async {
    try {
      if (file.path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File path is not available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final fileBytes = await File(file.path!).readAsBytes();

      if (fileBytes.length > 10 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File size exceeds 10MB limit'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final base64File = base64Encode(fileBytes);
      await _sendMessage(
        fileBase64: base64File,
        fileName: file.name,
        messageType: 'file',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Voice recording with translation
  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );

        setState(() {
          _isRecording = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });

      if (_recordedFilePath != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.mic, color: Colors.teal[800]),
                const SizedBox(width: 8),
                const Text('Voice Message'),
              ],
            ),
            content: const Text('Choose how to send your voice message:'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _sendVoiceMessage(_recordedFilePath!);
                },
                child: const Text('Send Voice'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  translateVoiceMessage(_recordedFilePath!);
                },
                child: const Text('Translate First'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _recordedFilePath = null;
                  });
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to stop recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> translateVoiceMessage(String audioFilePath) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VoiceTranslationScreen(),
      ),
    );
  }

  Future<void> _sendVoiceMessage(String voicePath) async {
    try {
      final voiceBytes = await File(voicePath).readAsBytes();

      if (voiceBytes.length > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice message too large'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final base64Voice = base64Encode(voiceBytes);
      await _sendMessage(
        voiceBase64: base64Voice,
        voiceFileName: path.basename(voicePath),
        messageType: 'voice',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send voice message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Main send message function
  Future<void> _sendMessage({
    String? text,
    String? fileBase64,
    String? fileName,
    String? voiceBase64,
    String? voiceFileName,
    String? imageBase64,
    String? imageName,
    String messageType = 'text',
  }) async {
    String messageText = text ?? _messageController.text.trim();

    if (messageText.isEmpty &&
        fileBase64 == null &&
        voiceBase64 == null &&
        imageBase64 == null) return;

    try {
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc((await FirebaseFirestore.instance
          .collection('custom_ids')
          .where('customId', isEqualTo: widget.currentUserCustomId)
          .get())
          .docs[0]['userId'])
          .collection('profiledetails')
          .doc('profile')
          .get();

      final messageData = {
        'text': messageText,
        'senderCustomId': widget.currentUserCustomId,
        'senderName': currentUserDoc['name'] ?? 'Unknown',
        'timestamp': FieldValue.serverTimestamp(),
        'type': messageType,
        'originalLanguage': _selectedLanguage,
        'isPinned': false,
        if (fileBase64 != null) 'fileBase64': fileBase64,
        if (fileName != null) 'fileName': fileName,
        if (voiceBase64 != null) 'voiceBase64': voiceBase64,
        if (voiceFileName != null) 'voiceFileName': voiceFileName,
        if (imageBase64 != null) 'imageBase64': imageBase64,
        if (imageName != null) 'imageName': imageName,
      };

      if (_isGroup) {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('messages')
            .add(messageData);

        final memberDocs = await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.selectedCustomId)
            .collection('members')
            .get();

        for (var member in memberDocs.docs) {
          if (member['userId'] != widget.currentUserCustomId) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(member['userId'])
                .collection('unread_counts')
                .doc('counts')
                .set({
              widget.selectedCustomId: FieldValue.increment(1)
            }, SetOptions(merge: true));
          }

          await FirebaseFirestore.instance
              .collection('users')
              .doc(member['userId'])
              .collection('messages')
              .doc(widget.selectedCustomId)
              .set({
            'lastMessage': messageText.isNotEmpty ? messageText : '$messageType message',
            'timestamp': FieldValue.serverTimestamp(),
            'senderCustomId': widget.currentUserCustomId,
            'senderName': currentUserDoc['name'] ?? 'Unknown',
            'groupId': widget.selectedCustomId,
            'groupName': widget.selectedUserName,
            'type': messageType,
          }, SetOptions(merge: true));
        }
      } else {
        final chatRoomId = _getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId);
        await FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(chatRoomId)
            .collection('messages')
            .add(messageData);

        final recipientUserId = (await FirebaseFirestore.instance
            .collection('custom_ids')
            .where('customId', isEqualTo: widget.selectedCustomId)
            .get())
            .docs[0]['userId'];

        await FirebaseFirestore.instance
            .collection('users')
            .doc(recipientUserId)
            .collection('unread_counts')
            .doc('counts')
            .set({
          widget.currentUserCustomId: FieldValue.increment(1)
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance
            .collection('users')
            .doc(recipientUserId)
            .collection('messages')
            .doc(widget.currentUserCustomId)
            .set({
          'lastMessage': messageText.isNotEmpty ? messageText : '$messageType message',
          'timestamp': FieldValue.serverTimestamp(),
          'senderCustomId': widget.currentUserCustomId,
          'senderName': currentUserDoc['name'] ?? 'Unknown',
          'type': messageType,
        }, SetOptions(merge: true));
      }

      _messageController.clear();
      _sendTypingIndicator(false);
      _scrollToBottom();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show error message
  void _showError(String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _sendTypingIndicator(false);
    _messageController.removeListener(_onTextChanged);
    _callService.dispose();
    _groupCallService?.dispose(); // Dispose group call service
    _messageController.dispose();
    _recorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getChatRoomId(String customId1, String customId2) {
    return customId1.compareTo(customId2) < 0
        ? '${customId1}_$customId2'
        : '${customId2}_$customId1';
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while initializing
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.selectedUserName),
          backgroundColor: Colors.teal[800],
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Add debug info at the top of build method
    print('Build - isGroup: $_isGroup, isGroupOwner: $_isGroupOwner, currentUserCustomId: ${widget.currentUserCustomId}');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.selectedUserPhotoURL.startsWith('assets/')
                  ? AssetImage(widget.selectedUserPhotoURL)
                  : NetworkImage(widget.selectedUserPhotoURL) as ImageProvider,
              radius: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.selectedUserName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (_isRealTimeTranslationEnabled)
                    Text(
                      'Auto-translate: ${_languageNames[_selectedLanguage]}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  // Add debug info to see current status
                  if (_isGroup)
                    Text(
                      'Group${_isGroupOwner ? ' (Owner)' : ''}',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.teal[800],
        actions: [
          // Pin messages button for group owners
          if (_isGroup && _isGroupOwner)
            IconButton(
              icon: const Icon(Icons.push_pin),
              onPressed: _showAllPinnedMessages,
              tooltip: 'View Pinned Messages',
            ),
          CallIconBar(
            isGroup: _isGroup,
            canStartPrivateCall: canStartPrivateCall(),
            canStartGroupCall: canStartGroupCall(),
            onPrivateVideoCall: startPrivateVideoCall,
            onPrivateVoiceCall: startPrivateVoiceCall,
            onGroupVideoCall: startGroupVideoCall,
            onGroupVoiceCall: startGroupVoiceCall,
          ),
          IconButton(
            icon: const Icon(Icons.translate),
            onPressed: _showLanguageSettings,
            tooltip: 'Language Settings',
          ),
          // Debug button (remove in production)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) async {
              switch (value) {
                case 'debug':
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Debug Info'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Is Group: $_isGroup'),
                          Text('Is Group Owner: $_isGroupOwner'),
                          Text('Current User ID: ${widget.currentUserCustomId}'),
                          Text('Selected ID: ${widget.selectedCustomId}'),
                          Text('Is Initialized: $_isInitialized'),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () async {
                              // Force re-check group owner status
                              await _checkIfGroupOwner();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Group owner status: $_isGroupOwner'),
                                  backgroundColor: _isGroupOwner ? Colors.green : Colors.red,
                                ),
                              );
                            },
                            child: const Text('Re-check Group Owner'),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'debug',
                child: Text('Debug Info'),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal[50]!, Colors.white],
          ),
        ),
        child: Column(
          children: [
            // Messages list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _isGroup
                    ? FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.selectedCustomId)
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots()
                    : FirebaseFirestore.instance
                    .collection('chat_rooms')
                    .doc(_getChatRoomId(widget.currentUserCustomId, widget.selectedCustomId))
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        _getLocalizedString('no_messages'),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final message = snapshot.data!.docs[index];
                      final messageData = message.data() as Map<String, dynamic>;

                      // Debug print for each message
                      print('Message ${index}: isPinned=${messageData['isPinned']}, isGroup=$_isGroup, isGroupOwner=$_isGroupOwner');

                      return MessageBubble(
                        message: message,
                        isMe: message['senderCustomId'] == widget.currentUserCustomId,
                        isGroup: _isGroup,
                        isRealTimeTranslationEnabled: _isRealTimeTranslationEnabled,
                        showOriginalText: _showOriginalText,
                        selectedLanguage: _selectedLanguage,
                        languageNames: _languageNames,
                        translationService: _translationService,
                        fileService: _fileService,
                        selectedUserPhotoURL: widget.selectedUserPhotoURL,
                        groupId: _isGroup ? widget.selectedCustomId : null,
                        isGroupOwner: _isGroupOwner,
                        currentUserCustomId: widget.currentUserCustomId,
                      );
                    },
                  );
                },
              ),
            ),

            // Input area
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickFile,
                    color: Colors.teal[700],
                  ),
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _pickImage,
                    color: Colors.teal[700],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}), // Trigger rebuild for send button
                      decoration: InputDecoration(
                        hintText: _getLocalizedString('type_message'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  if (_messageController.text.isEmpty)
                    IconButton(
                      icon: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: _isRecording ? Colors.red : Colors.teal[700],
                      ),
                      onPressed: _isRecording ? _stopRecording : _startRecording,
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.send, color: Colors.teal[700]),
                      onPressed: () => _sendMessage(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}