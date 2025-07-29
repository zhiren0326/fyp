/*
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

class FileUploadService {
  static final ImagePicker _imagePicker = ImagePicker();

  /// Convert a file to Base64 string
  static Future<String?> convertFileToBase64(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      return base64String;
    } catch (e) {
      print('Error converting file to Base64: $e');
      return null;
    }
  }

  /// Convert multiple files to Base64 strings
  static Future<List<String>> convertFilesToBase64(List<File> files) async {
    List<String> base64Strings = [];

    for (File file in files) {
      final String? base64String = await convertFileToBase64(file);
      if (base64String != null) {
        base64Strings.add(base64String);
      }
    }

    return base64Strings;
  }

  /// Take a photo using camera
  static Future<File?> takePhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        return File(photo.path);
      }
      return null;
    } catch (e) {
      print('Error taking photo: $e');
      return null;
    }
  }

  /// Pick image from gallery
  static Future<File?> pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        return File(image.path);
      }
      return null;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  /// Pick multiple images from gallery
  static Future<List<File>> pickMultipleImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultipleImages(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      return images.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      print('Error picking multiple images: $e');
      return [];
    }
  }

  /// Pick files using file picker
  static Future<List<File>> pickFiles() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null) {
        return result.paths
            .where((path) => path != null)
            .map((path) => File(path!))
            .toList();
      }
      return [];
    } catch (e) {
      print('Error picking files: $e');
      return [];
    }
  }

  /// Show file picker options dialog
  static Future<List<File>?> showFilePickerDialog() async {
    return await pickFiles();
  }

  /// Get file type from extension
  static String getFileType(String fileName) {
    final String extension = path.extension(fileName).toLowerCase();

    switch (extension) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
        return 'image';
      case '.pdf':
        return 'pdf';
      case '.doc':
      case '.docx':
        return 'document';
      case '.txt':
        return 'text';
      default:
        return 'file';
    }
  }

  /// Get file size in a readable format
  static String getFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}*/
