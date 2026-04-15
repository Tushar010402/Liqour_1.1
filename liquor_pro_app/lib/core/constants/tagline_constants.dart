import 'package:flutter/material.dart';

/// Tagline data with signature color and icon for personalised feel
class TagLineInfo {
  final String text;
  final String icon;
  final Color color;
  final Color bgColor;
  const TagLineInfo(this.text, this.icon, this.color, this.bgColor);
}

/// All available taglines with their authentic colors and icons
class TagLineConstants {
  TagLineConstants._();

  static const String defaultTagLine = 'ॐ नमः शिवाय';

  static final List<TagLineInfo> options = [
    // Hindu devotional — native Devanagari
    TagLineInfo('ॐ नमः शिवाय', '🕉️', Color(0xFFE65100), Color(0xFFFFF3E0)),
    TagLineInfo('जय श्री राम', '🏹', Color(0xFFE53935), Color(0xFFFFEBEE)),
    TagLineInfo('जय माता दी', '🔱', Color(0xFFC62828), Color(0xFFFFCDD2)),
    TagLineInfo('हर हर महादेव', '🔱', Color(0xFF1565C0), Color(0xFFE3F2FD)),
    TagLineInfo('राधे राधे', '🦚', Color(0xFF1B5E20), Color(0xFFE8F5E9)),
    TagLineInfo('जय श्री कृष्णा', '🪈', Color(0xFF0D47A1), Color(0xFFE8EAF6)),
    TagLineInfo('जय बजरंग बली', '🙏', Color(0xFFFF6F00), Color(0xFFFFF8E1)),
    TagLineInfo('जय गणेश देवा', '🐘', Color(0xFFAD1457), Color(0xFFFCE4EC)),
    TagLineInfo('ॐ जय जगदीश हरे', '🙏', Color(0xFFE65100), Color(0xFFFBE9E7)),
    TagLineInfo('हरे कृष्णा हरे रामा', '🪷', Color(0xFF6A1B9A), Color(0xFFF3E5F5)),
    // Sikh — native Gurmukhi
    TagLineInfo('ਵਾਹਿਗੁਰੂ ਜੀ ਕਾ ਖ਼ਾਲਸਾ', '☬', Color(0xFFFF8F00), Color(0xFFFFF8E1)),
    TagLineInfo('ਸਤਿ ਸ਼੍ਰੀ ਅਕਾਲ', '☬', Color(0xFFEF6C00), Color(0xFFFFF3E0)),
    // Jain — native Devanagari
    TagLineInfo('जय जिनेन्द्र', '🪷', Color(0xFF00695C), Color(0xFFE0F2F1)),
    TagLineInfo('मिच्छामि दुक्कडम', '🙏', Color(0xFF00838F), Color(0xFFE0F7FA)),
    // Buddhist — native Pali/Devanagari
    TagLineInfo('नमो बुद्धाय', '☸️', Color(0xFFF9A825), Color(0xFFFFFDE7)),
    TagLineInfo('बुद्धं शरणं गच्छामि', '🪷', Color(0xFFFF8F00), Color(0xFFFFF8E1)),
    // Christian
    TagLineInfo('God is Great', '✝️', Color(0xFF5C6BC0), Color(0xFFE8EAF6)),
    TagLineInfo('Praise the Lord', '✝️', Color(0xFF3949AB), Color(0xFFE8EAF6)),
    // Muslim — native Arabic/Urdu
    TagLineInfo('بِسْمِ ٱللَّٰهِ', '☪️', Color(0xFF2E7D32), Color(0xFFE8F5E9)),
    TagLineInfo('ماشاءاللہ', '☪️', Color(0xFF1B5E20), Color(0xFFE8F5E9)),
    // Universal / Motivational
    TagLineInfo('Blessed & Grateful', '✨', Color(0xFF6A1B9A), Color(0xFFF3E5F5)),
    TagLineInfo('Work Hard, Stay Humble', '💪', Color(0xFF37474F), Color(0xFFECEFF1)),
    TagLineInfo('Live and Let Live', '🌿', Color(0xFF2E7D32), Color(0xFFE8F5E9)),
    TagLineInfo('Hustle with Heart', '🔥', Color(0xFFD84315), Color(0xFFFBE9E7)),
    TagLineInfo('Stay Positive', '☀️', Color(0xFFF57F17), Color(0xFFFFFDE7)),
  ];

  /// Migration map: old English text → new native text
  static const _legacyMap = {
    'Om Namah Shivaya': 'ॐ नमः शिवाय',
    'Jai Shri Ram': 'जय श्री राम',
    'Jai Mata Di': 'जय माता दी',
    'Har Har Mahadev': 'हर हर महादेव',
    'Radhe Radhe': 'राधे राधे',
    'Jai Shri Krishna': 'जय श्री कृष्णा',
    'Jai Bajrang Bali': 'जय बजरंग बली',
    'Jai Ganesh Deva': 'जय गणेश देवा',
    'Om Jai Jagdish Hare': 'ॐ जय जगदीश हरे',
    'Hare Krishna Hare Rama': 'हरे कृष्णा हरे रामा',
    'Waheguru Ji Ka Khalsa': 'ਵਾਹਿਗੁਰੂ ਜੀ ਕਾ ਖ਼ਾਲਸਾ',
    'Sat Sri Akal': 'ਸਤਿ ਸ਼੍ਰੀ ਅਕਾਲ',
    'Jai Jinendra': 'जय जिनेन्द्र',
    'Micchami Dukkadam': 'मिच्छामि दुक्कडम',
    'Namo Buddhaya': 'नमो बुद्धाय',
    'Buddham Sharanam Gacchami': 'बुद्धं शरणं गच्छामि',
    'Bismillah': 'بِسْمِ ٱللَّٰهِ',
    'MashaAllah': 'ماشاءاللہ',
  };

  /// Migrate old English tagline to native script
  static String migrateIfNeeded(String text) => _legacyMap[text] ?? text;

  /// Look up tagline info by text (handles old English values)
  static TagLineInfo getInfo(String text) {
    // Try exact match first
    final exact = options.where((t) => t.text == text);
    if (exact.isNotEmpty) return exact.first;
    // Try migrating old English text
    final migrated = migrateIfNeeded(text);
    return options.firstWhere(
      (t) => t.text == migrated,
      orElse: () => options.first,
    );
  }
}
