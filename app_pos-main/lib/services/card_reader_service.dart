import 'dart:async';
import 'package:flutter/services.dart';

/// Model to hold data extracted from a physical card reader
class CardData {
  final String cardNumber;
  final String holderName;
  final String expiryMonth;
  final String expiryYear;

  CardData({
    required this.cardNumber,
    required this.holderName,
    required this.expiryMonth,
    required this.expiryYear,
  });

  @override
  String toString() {
    return 'CardData(Number: $cardNumber, Name: $holderName, Expiry: $expiryMonth/$expiryYear)';
  }
}

/// Service to listen for hardware card reader input (HID/Keyboard mode)
/// Most cheap USB/Bluetooth card readers act as an external keyboard.
/// They "type" a sequence of characters starting with sentinels like '%' or ';'
class CardReaderService {
  static final CardReaderService _instance = CardReaderService._internal();
  factory CardReaderService() => _instance;
  CardReaderService._internal();

  final _cardDataController = StreamController<CardData>.broadcast();
  Stream<CardData> get onCardRead => _cardDataController.stream;

  String _buffer = '';
  DateTime? _lastKeyEventTime;
  
  // Time threshold to distinguish between human typing and hardware "typing" (in milliseconds)
  // Card readers usually "type" extremely fast (interval < 20ms)
  final int _typingThreshold = 50; 

  /// Call this from a global [RawKeyboardListener] or [Focus] widget in your app
  void handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    final String? character = event.character;
    if (character == null) return;

    final now = DateTime.now();

    // If there's a long pause, clear the buffer as it's likely a new read or human typing
    if (_lastKeyEventTime != null && 
        now.difference(_lastKeyEventTime!).inMilliseconds > _typingThreshold) {
      if (!_buffer.startsWith('%') && !_buffer.startsWith(';')) {
         _buffer = '';
      }
    }

    _lastKeyEventTime = now;

    // Detect 'Enter' key which usually signals the end of the swipe
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_buffer.isNotEmpty) {
        _processBuffer(_buffer);
        _buffer = '';
      }
      return;
    }

    _buffer += character;

    // Optional: Max buffer length safety
    if (_buffer.length > 200) _buffer = '';
  }

  void _processBuffer(String raw) {
    // Standard Track 1 Format: %B[PAN]^[Name]^[Expiry][Other]?
    // Standard Track 2 Format: ;[PAN]=[Expiry][Other]?
    
    try {
      if (raw.startsWith('%B')) {
        _parseTrack1(raw);
      } else if (raw.startsWith(';')) {
        _parseTrack2(raw);
      }
    } catch (e) {
      print('Error parsing card data: $e');
    }
  }

  /// Parses Track 1 (Contains Name and Number)
  /// Example: %B1234567812345678^NAME/HOLDER^2512101...?
  void _parseTrack1(String data) {
    final parts = data.substring(2).split('^');
    if (parts.length >= 3) {
      String number = parts[0].trim();
      String name = parts[1].trim().replaceAll('/', ' '); // Convert 'NAME/SURNAME' to 'NAME SURNAME'
      String expiryRaw = parts[2]; // Usually YYMM
      
      if (expiryRaw.length >= 4) {
        String year = expiryRaw.substring(0, 2);
        String month = expiryRaw.substring(2, 4);
        
        _cardDataController.add(CardData(
          cardNumber: number,
          holderName: name.toUpperCase(),
          expiryMonth: month,
          expiryYear: year,
        ));
      }
    }
  }

  /// Parses Track 2 (Contains Number and Expiry, but no Name)
  /// Example: ;1234567812345678=2512101...?
  void _parseTrack2(String data) {
    final clean = data.substring(1);
    final parts = clean.split('=');
    if (parts.length >= 2) {
      String number = parts[0].trim();
      String expiryRaw = parts[1]; // Usually YYMM
      
      if (expiryRaw.length >= 4) {
        String year = expiryRaw.substring(0, 2);
        String month = expiryRaw.substring(2, 4);
        
        _cardDataController.add(CardData(
          cardNumber: number,
          holderName: 'KHACH HANG', // Track 2 doesn't have name info
          expiryMonth: month,
          expiryYear: year,
        ));
      }
    }
  }

  void dispose() {
    _cardDataController.close();
  }
}
