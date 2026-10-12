import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase
  await Firebase.initializeApp();

  // 2. Explicitly configure Firestore for robust offline usage
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    // Set to unlimited, or set a cap like 104857600 (100 MB)
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => PosProvider())],
      child: const FriendsTiffinApp(),
    ),
  );
}

Future<String?> pickLocalImageDataUrl({int maxBytes = 1600000}) async {
  // file_picker v12 uses static methods on FilePicker. The old
  // FilePicker.platform API was removed as part of the v12 migration.
  final PlatformFile? file = await FilePicker.pickFile(type: FileType.image);
  if (file == null) return null; // User cancelled the picker.

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception('Could not read the selected image.');
  }
  if (bytes.length > maxBytes) {
    throw Exception('Image is too large. Choose an image below 1.6 MB.');
  }

  final fileName = file.name.toLowerCase();
  final mime = fileName.endsWith('.png')
      ? 'image/png'
      : fileName.endsWith('.webp')
      ? 'image/webp'
      : fileName.endsWith('.gif')
      ? 'image/gif'
      : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

class AppMenuImage extends StatelessWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;
  final Color? color;
  final BlendMode? colorBlendMode;

  const AppMenuImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
    this.color,
    this.colorBlendMode,
  });

  Widget _fallback() =>
      fallback ??
      Container(
        width: width,
        height: height,
        color: AppTheme.primaryMuted,
        alignment: Alignment.center,
        child: const Icon(Icons.fastfood_rounded, color: AppTheme.primary),
      );

  @override
  Widget build(BuildContext context) {
    if (source.trim().isEmpty) return _fallback();
    if (source.startsWith('data:image')) {
      try {
        final comma = source.indexOf(',');
        if (comma < 0) return _fallback();
        return Image.memory(
          base64Decode(source.substring(comma + 1)),
          width: width,
          height: height,
          fit: fit,
          color: color,
          colorBlendMode: colorBlendMode,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _fallback(),
        );
      } catch (_) {
        return _fallback();
      }
    }
    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      color: color,
      colorBlendMode: colorBlendMode,
      errorBuilder: (context, error, stackTrace) => _fallback(),
    );
  }
}

// ============================================================================

// DESIGN SYSTEM CONSTANTS & TOKENS
// ============================================================================
class AppTheme {
  // Premium hospitality palette — deep emerald, warm ivory, restrained saffron.
  static const Color primary = Color(0xFF123D2A);
  static const Color primaryDark = Color(0xFF0B2A1D);
  static const Color primaryLight = Color(0xFF235C43);
  static const Color primaryMuted = Color(0xFFEAF2ED);
  static const Color accent = Color(0xFFF59E0B);
  static const Color accentDark = Color(0xFFD97706);
  static const Color accentLight = Color(0xFFFFF7E6);
  static const Color surface = Color(0xFFF7F8F5);
  static const Color surfaceAlt = Color(0xFFF0F3EF);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF17211B);
  static const Color textSecondary = Color(0xFF6B756E);
  static const Color border = Color(0xFFE5E9E6);
  static const Color info = Color(0xFF2563EB);
  static const Color success = Color(0xFF16A34A);
  static const Color error = Color(0xFFDC2626);

  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusXl = 28;

  static final List<BoxShadow> elevationLow = [
    BoxShadow(
      color: primary.withValues(alpha: 0.045),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> elevationCard = [
    BoxShadow(
      color: primary.withValues(alpha: 0.075),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> elevationFloat = [
    BoxShadow(
      color: primary.withValues(alpha: 0.14),
      blurRadius: 32,
      offset: const Offset(0, 14),
    ),
  ];
}

// ============================================================================
// DATA MODELS
// ============================================================================
class MenuItem {
  String id;
  String name;
  double price;
  String category;
  String imageUrl;
  bool isAvailable;

  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    required this.imageUrl,
    this.isAvailable = true,
  });

  MenuItem clone() => MenuItem(
    id: id,
    name: name,
    price: price,
    category: category,
    imageUrl: imageUrl,
    isAvailable: isAvailable,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'category': category,
    'imageUrl': imageUrl,
    'isAvailable': isAvailable,
  };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0,
    category: json['category']?.toString() ?? 'Tiffin',
    imageUrl: json['imageUrl']?.toString() ?? '',
    isAvailable: json['isAvailable'] as bool? ?? true,
  );
}

class CartItem {
  final MenuItem item;
  int quantity;

  CartItem({required this.item, this.quantity = 1});
  double get total => item.price * quantity;
  CartItem clone() => CartItem(item: item.clone(), quantity: quantity);

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'quantity': quantity,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    item: MenuItem.fromJson(
      Map<String, dynamic>.from(json['item'] as Map? ?? {}),
    ),
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  );
}

String formatTokenLabel(int number) =>
    'Token ${number.toString().padLeft(3, '0')}';

class ActiveBill {
  final String id;
  String label;
  Map<String, CartItem> items;
  DateTime createdAt;
  String orderType;

  ActiveBill({
    required this.id,
    required this.label,
    Map<String, CartItem>? items,
    DateTime? createdAt,
    this.orderType = 'DINE IN',
  }) : items = items ?? {},
       createdAt = createdAt ?? DateTime.now();

  int get totalCount => items.values.fold<int>(0, (acc, i) => acc + i.quantity);
  double get totalAmount =>
      items.values.fold<double>(0.0, (acc, i) => acc + i.total);

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
    'orderType': orderType,
    'items': items.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory ActiveBill.fromJson(Map<String, dynamic> json) {
    final rawItems = Map<String, dynamic>.from(json['items'] as Map? ?? {});
    return ActiveBill(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      label: json['label']?.toString() ?? formatTokenLabel(1),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      orderType: json['orderType']?.toString() ?? 'DINE IN',
      items: rawItems.map(
        (key, value) => MapEntry(
          key,
          CartItem.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }
}

class CompletedOrder {
  final String billId;
  final String billLabel;
  final DateTime timestamp;
  final List<CartItem> items;
  final double totalAmount;
  final double tenderAmount;
  final double changeAmount;
  final String paymentMethod;
  final String orderType;
  bool isVoided;
  String voidReason;
  DateTime? voidedAt;

  CompletedOrder({
    required this.billId,
    required this.billLabel,
    required this.timestamp,
    required this.items,
    required this.totalAmount,
    this.tenderAmount = 0.0,
    this.changeAmount = 0.0,
    required this.paymentMethod,
    this.orderType = 'DINE IN',
    this.isVoided = false,
    this.voidReason = '',
    this.voidedAt,
  });

  Map<String, dynamic> toJson() => {
    'billId': billId,
    'billLabel': billLabel,
    'timestamp': timestamp.toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
    'totalAmount': totalAmount,
    'tenderAmount': tenderAmount,
    'changeAmount': changeAmount,
    'paymentMethod': paymentMethod,
    'orderType': orderType,
    'isVoided': isVoided,
    'voidReason': voidReason,
    'voidedAt': voidedAt?.toIso8601String(),
  };

  factory CompletedOrder.fromJson(Map<String, dynamic> json) => CompletedOrder(
    billId: json['billId']?.toString() ?? '',
    billLabel: json['billLabel']?.toString() ?? '',
    timestamp:
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now(),
    items: (json['items'] as List? ?? [])
        .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
    tenderAmount: (json['tenderAmount'] as num?)?.toDouble() ?? 0,
    changeAmount: (json['changeAmount'] as num?)?.toDouble() ?? 0,
    paymentMethod: json['paymentMethod']?.toString() ?? 'CASH',
    orderType: json['orderType']?.toString() ?? 'DINE IN',
    isVoided: json['isVoided'] as bool? ?? false,
    voidReason: json['voidReason']?.toString() ?? '',
    voidedAt: DateTime.tryParse(json['voidedAt']?.toString() ?? ''),
  );
}

class DayCloseRecord {
  final String id;
  final DateTime timestamp;
  final double expectedCash;
  final double countedCash;
  final double variance;
  final double upiSales;
  final double totalSales;
  final int orderCount;
  final double cashExpenses;
  final double ownerWithdrawals;
  final double cashAdded;
  final double operatingExpenses;

  DayCloseRecord({
    required this.id,
    required this.timestamp,
    required this.expectedCash,
    required this.countedCash,
    required this.variance,
    required this.upiSales,
    required this.totalSales,
    required this.orderCount,
    this.cashExpenses = 0,
    this.ownerWithdrawals = 0,
    this.cashAdded = 0,
    this.operatingExpenses = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'expectedCash': expectedCash,
    'countedCash': countedCash,
    'variance': variance,
    'upiSales': upiSales,
    'totalSales': totalSales,
    'orderCount': orderCount,
    'cashExpenses': cashExpenses,
    'ownerWithdrawals': ownerWithdrawals,
    'cashAdded': cashAdded,
    'operatingExpenses': operatingExpenses,
  };

  factory DayCloseRecord.fromJson(Map<String, dynamic> json) => DayCloseRecord(
    id: json['id']?.toString() ?? '',
    timestamp:
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now(),
    expectedCash: (json['expectedCash'] as num?)?.toDouble() ?? 0,
    countedCash: (json['countedCash'] as num?)?.toDouble() ?? 0,
    variance: (json['variance'] as num?)?.toDouble() ?? 0,
    upiSales: (json['upiSales'] as num?)?.toDouble() ?? 0,
    totalSales: (json['totalSales'] as num?)?.toDouble() ?? 0,
    orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
    cashExpenses: (json['cashExpenses'] as num?)?.toDouble() ?? 0,
    ownerWithdrawals: (json['ownerWithdrawals'] as num?)?.toDouble() ?? 0,
    cashAdded: (json['cashAdded'] as num?)?.toDouble() ?? 0,
    operatingExpenses: (json['operatingExpenses'] as num?)?.toDouble() ?? 0,
  );
}

class ExpenseRecord {
  final String id;
  DateTime timestamp;
  String kind; // EXPENSE, OWNER WITHDRAWAL, CASH ADDED
  String category;
  String description;
  double amount;
  String paymentMethod; // CASH, UPI, BANK
  String supplier;
  String notes;
  String receiptDataUrl;

  ExpenseRecord({
    required this.id,
    required this.timestamp,
    this.kind = 'EXPENSE',
    required this.category,
    required this.description,
    required this.amount,
    this.paymentMethod = 'CASH',
    this.supplier = '',
    this.notes = '',
    this.receiptDataUrl = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'kind': kind,
    'category': category,
    'description': description,
    'amount': amount,
    'paymentMethod': paymentMethod,
    'supplier': supplier,
    'notes': notes,
    'receiptDataUrl': receiptDataUrl,
  };

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) => ExpenseRecord(
    id:
        json['id']?.toString() ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    timestamp:
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now(),
    kind: json['kind']?.toString() ?? 'EXPENSE',
    category: json['category']?.toString() ?? 'Miscellaneous',
    description: json['description']?.toString() ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    paymentMethod: json['paymentMethod']?.toString() ?? 'CASH',
    supplier: json['supplier']?.toString() ?? '',
    notes: json['notes']?.toString() ?? '',
    receiptDataUrl: json['receiptDataUrl']?.toString() ?? '',
  );

  bool get affectsOperatingExpense => kind == 'EXPENSE';
  bool get affectsCashDrawer => paymentMethod == 'CASH';
}

class StoreTemplate {
  String storeName;
  String tagline;
  String address;
  String phone;
  List<String> upiIds;
  String footerMessage;
  String subFooter;
  String soundboxLanguage;
  String logoDataUrl;

  StoreTemplate({
    this.storeName = 'FRIENDS TIFFIN CENTER',
    this.tagline = 'நல்ல சாப்பாடு • நல்ல நட்பு',
    this.address = 'No. 12, Beach Road, Chennai - 600001',
    this.phone = '98765 43210',
    List<String>? upiIds,
    String? upiId,
    this.footerMessage = 'Thank You! / நன்றி!',
    this.subFooter = 'Good Food • Good Friends',
    this.soundboxLanguage = 'en-IN',
    this.logoDataUrl = '',
  }) : upiIds = upiIds ?? (upiId != null ? [upiId] : ['friendstiffin@okaxis']);

  String get upiId => upiIds.isNotEmpty ? upiIds.first : 'friendstiffin@okaxis';
  set upiId(String val) {
    if (upiIds.isEmpty) {
      upiIds = [val];
    } else {
      upiIds[0] = val;
    }
  }

  Map<String, dynamic> toJson() => {
    'storeName': storeName,
    'tagline': tagline,
    'address': address,
    'phone': phone,
    'upiIds': upiIds,
    'upiId': upiId,
    'footerMessage': footerMessage,
    'subFooter': subFooter,
    'soundboxLanguage': soundboxLanguage,
    'logoDataUrl': logoDataUrl,
  };

  void applyJson(Map<String, dynamic> json) {
    storeName = json['storeName']?.toString() ?? storeName;
    tagline = json['tagline']?.toString() ?? tagline;
    address = json['address']?.toString() ?? address;
    phone = json['phone']?.toString() ?? phone;
    if (json['upiIds'] is List) {
      upiIds = (json['upiIds'] as List).map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } else if (json['upiId'] != null) {
      upiIds = [json['upiId'].toString()];
    }
    if (upiIds.isEmpty) {
      upiIds = ['friendstiffin@okaxis'];
    }
    footerMessage = json['footerMessage']?.toString() ?? footerMessage;
    subFooter = json['subFooter']?.toString() ?? subFooter;
    soundboxLanguage = json['soundboxLanguage']?.toString() ?? soundboxLanguage;
    logoDataUrl = json['logoDataUrl']?.toString() ?? logoDataUrl;
  }
}
// ============================================================================
// AUTHENTICATION & LOGIN SCREENS (Firebase Auth & Role Verification Edition)
// ============================================================================
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isInitializing = true;
  bool _isPosLoaded = false;
  User? _unverifiedUser;

  @override
  void initState() {
    super.initState();
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (!mounted) return;
      if (user != null && user.email != null) {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;
        
        if (refreshedUser != null && !refreshedUser.emailVerified && !refreshedUser.email!.endsWith('@staff.pos')) {
          if (mounted) {
            setState(() {
              _unverifiedUser = refreshedUser;
              _isPosLoaded = false;
              _isInitializing = false;
            });
          }
          return;
        }

        // Email is verified -> load POS database
        if (!mounted) return;
        
        // We need to fetch from Provider to know what DB to load.
        // If it's a staff account, they will have the owner's email saved in SharedPreferences.
        // Actually, we can just call login() on the Provider without an email, and it will load from SharedPreferences.
        // Let's modify PosProvider to have a safe init method.
        // For now, we'll assume PosProvider handles loading from SharedPreferences if we pass the user's email, or we can just call an init method.
        // Let's use the user's email for now. If they are staff, they already saved the owner email to SharedPreferences.
        
        // So we will call a new method init() on PosProvider to load from SharedPreferences.
        await Provider.of<PosProvider>(context, listen: false).initDbConnection(refreshedUser?.email ?? user.email!);

        if (mounted) {
          setState(() {
            _unverifiedUser = null;
            _isPosLoaded = true;
            _isInitializing = false;
          });
        }
      } else {
        // User is logged out
        if (mounted) {
          setState(() {
            _unverifiedUser = null;
            _isPosLoaded = false;
            _isInitializing = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: AppTheme.primary,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_unverifiedUser != null) {
      return EmailVerificationScreen(user: _unverifiedUser!);
    }

    return _isPosLoaded ? const DashboardScreen() : const LoginScreen();
  }
}

class EmailVerificationScreen extends StatefulWidget {
  final User user;
  const EmailVerificationScreen({super.key, required this.user});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isResending = false;

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);
    try {
      await widget.user.reload();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.emailVerified) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified successfully! Opening POS...'),
            backgroundColor: AppTheme.success,
          ),
        );
        // Reload login
        await Provider.of<PosProvider>(context, listen: false).login(currentUser.email!);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email not verified yet. Please check your inbox or spam folder.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error checking email verification: $e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendVerification() async {
    setState(() => _isResending = true);
    try {
      await widget.user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification email resent to ${widget.user.email}'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resend verification email: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryMuted,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.mark_email_unread_rounded, size: 36, color: AppTheme.primary),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Verify Your Email',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'We sent a verification link to:\n${widget.user.email}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please open your email and click the link to activate your POS account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isChecking ? null : _checkVerification,
                          icon: _isChecking
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.verified_user_rounded),
                          label: const Text('I\'VE VERIFIED (CONTINUE)'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isResending ? null : _resendVerification,
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text(_isResending ? 'Resending...' : 'Resend Verification Email'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Back to Login'),
                        style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _ownerStoreEmailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isLoginMode = true; // Toggles between Login and Sign Up
  String _selectedRole = 'Owner'; // 'Owner' or 'Staff'

  @override
  void dispose() {
    _emailCtrl.dispose();
    _ownerStoreEmailCtrl.dispose();
    _usernameCtrl.dispose();
    _mobileCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim().toLowerCase();

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Mail ID in the field above to receive a reset link.')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset link sent! Please check your email.'),
          backgroundColor: AppTheme.success,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to send reset email'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _submitAuthForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final password = _passwordCtrl.text.trim();

    try {
      if (_isLoginMode) {
        // Login Existing User
        String loginId = _emailCtrl.text.trim().toLowerCase();
        if (!loginId.contains('@')) {
          loginId = '$loginId@staff.pos';
        }
        
        final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: loginId,
          password: password,
        );
        
        // Staff Verification Check
        if (loginId.endsWith('@staff.pos')) {
          final staffId = loginId.split('@')[0];
          final prefs = await SharedPreferences.getInstance();
          String? storeEmail = prefs.getString('pos_user_email');

          // Look up store email from global index if missing locally
          if (storeEmail == null || storeEmail.isEmpty) {
            try {
              final lookupDoc = await FirebaseFirestore.instance
                  .collection('staff_accounts')
                  .doc(staffId)
                  .get();
              if (lookupDoc.exists) {
                storeEmail = lookupDoc.data()?['storeEmail']?.toString();
                if (storeEmail != null && storeEmail.isNotEmpty) {
                  await prefs.setString('pos_user_email', storeEmail);
                }
              }
            } catch (_) {}
          }

          if (storeEmail != null && storeEmail.isNotEmpty) {
             DocumentSnapshot staffDoc = await FirebaseFirestore.instance
                  .collection('pos_users')
                  .doc(storeEmail)
                  .collection('staff')
                  .doc(staffId)
                  .get();

             if (!staffDoc.exists) {
                staffDoc = await FirebaseFirestore.instance
                    .collection('staff_requests')
                    .doc(staffId)
                    .get();
             }

             if (!staffDoc.exists) {
                staffDoc = await FirebaseFirestore.instance
                    .collection('restaurants')
                    .doc(storeEmail)
                    .collection('staff')
                    .doc(staffId)
                    .get();
             }
                  
             if (staffDoc.exists && (staffDoc.data() as Map<String, dynamic>?)?['status'] != 'active') {
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Account pending verification. The Owner must accept your request first.'),
                    backgroundColor: AppTheme.error,
                  ),
                );
                return;
             }
          }
        }

        if (userCred.user != null && !userCred.user!.emailVerified && !loginId.endsWith('@staff.pos')) {
          await userCred.user!.sendEmailVerification();
        }
      } else {
        // Create New Account
        final role = _selectedRole;
        
        if (role == 'Owner') {
          final email = _emailCtrl.text.trim().toLowerCase();
          final username = _usernameCtrl.text.trim();
          
          final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          await userCredential.user?.updateDisplayName('$username (Owner)');
          await userCredential.user?.sendEmailVerification();

          if (mounted) {
            final pos = Provider.of<PosProvider>(context, listen: false);
            await pos.setOwnerDeviceMode(true);
            await pos.login(email);
          }
        } else {
          // Staff Account Creation
          final storeEmail = _ownerStoreEmailCtrl.text.trim().toLowerCase();
          final staffName = _usernameCtrl.text.trim();
          final staffMobile = _mobileCtrl.text.trim();

          final staffSnapshot = await FirebaseFirestore.instance
              .collection('pos_users')
              .doc(storeEmail)
              .collection('staff')
              .get();
              
          int staffCount = staffSnapshot.docs.length + 1;

          // Find max numeric staff ID from existing records in Firestore
          for (final doc in staffSnapshot.docs) {
            final idNum = int.tryParse(doc.id) ?? int.tryParse(doc.id.replaceAll(RegExp(r'[^0-9]'), ''));
            if (idNum != null && idNum >= staffCount) {
              staffCount = idNum + 1;
            }
          }

          UserCredential? userCredential;
          String staffId = '';
          String email = '';

          // Auto-increment numeric staff ID if email already exists in Firebase Auth to prevent collision
          while (userCredential == null) {
            staffId = staffCount.toString().padLeft(4, '0'); // e.g. 0001, 0002, 0003
            email = '$staffId@staff.pos'; // e.g. 0001@staff.pos, 0002@staff.pos
            
            try {
              userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: email,
                password: password,
              );
            } on FirebaseAuthException catch (e) {
              if (e.code == 'email-already-in-use') {
                staffCount++;
                if (staffCount > 9999) rethrow; // Safety upper bound limit
              } else {
                rethrow;
              }
            }
          }

          await userCredential.user?.updateDisplayName('$staffName (Staff ID: $staffId)');

          // 1. Save staff request to Owner's pos_users collection
          final staffData = {
            'id': staffId,
            'name': staffName,
            'mobile': staffMobile,
            'status': 'pending', // Pending owner approval
            'storeEmail': storeEmail,
            'email': email,
            'role': 'Staff',
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          };

          try {
            await FirebaseFirestore.instance
                .collection('pos_users')
                .doc(storeEmail)
                .collection('staff')
                .doc(staffId)
                .set(staffData);
          } catch (e) {
            debugPrint('Could not save staff request in pos_users: $e');
          }

          // 2. Also save to restaurants collection for full database consistency
          try {
            await FirebaseFirestore.instance
                .collection('restaurants')
                .doc(storeEmail)
                .collection('staff')
                .doc(staffId)
                .set(staffData);
          } catch (e) {
            debugPrint('Could not save staff request in restaurants: $e');
          }

          // 3. Save global staff account lookup so staff can log in from any device
          try {
            await FirebaseFirestore.instance
                .collection('staff_accounts')
                .doc(staffId)
                .set({
              'staffId': staffId,
              'storeEmail': storeEmail,
              'email': email,
              'name': staffName,
              'createdAt': DateTime.now().toIso8601String(),
            });
          } catch (e) {
            debugPrint('Could not save staff lookup: $e');
          }

          // Save the owner email for this staff device so they can reconnect
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pos_user_email', storeEmail);
          
          // Log out the pending user immediately so they can't access the POS
          await FirebaseAuth.instance.signOut();
          
          if (mounted) {
            setState(() {
               _isLoading = false;
               _isLoginMode = true; // Switch back to login screen
            });
            
             showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('Staff Account Created'),
                  content: Text('Your Staff Login ID is:\n\n$staffId\n\nA request has been sent to the Owner ($storeEmail). They must verify and accept your account before you can log in and use the POS.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('OK'),
                    )
                  ],
                )
             );
             return; // Stop execution to prevent logging in
          }
        }
      }

    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      _showError(e);
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unexpected error occurred: $e')),
      );
    }
  }

  void _showError(FirebaseAuthException e) {
    String message = 'Authentication failed.';
    switch (e.code) {
      case 'user-not-found':
        message = 'No account found for this email. Please sign up.';
        break;
      case 'wrong-password':
      case 'invalid-credential':
        message = 'Incorrect password or email.';
        break;
      case 'email-already-in-use':
        message = 'An account already exists for this email.';
        break;
      case 'weak-password':
        message = 'Password is too weak. Use at least 6 characters.';
        break;
      case 'invalid-email':
        message = 'The email address is badly formatted.';
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryMuted,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        size: 40,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isLoginMode ? 'Welcome Back' : 'Create Account',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isLoginMode
                          ? 'Sign in to your restaurant counter'
                          : 'Set up your cloud-synced POS account',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Role Selection on Sign Up Mode
                    if (!_isLoginMode) ...[
                      const Text(
                        'Select Account Role:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('👑 Owner')),
                              selected: _selectedRole == 'Owner',
                              selectedColor: AppTheme.primary,
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _selectedRole == 'Owner' ? Colors.white : AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (selected) {
                                if (selected) setState(() => _selectedRole = 'Owner');
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('👔 Staff')),
                              selected: _selectedRole == 'Staff',
                              selectedColor: AppTheme.primary,
                              backgroundColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _selectedRole == 'Staff' ? Colors.white : AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (selected) {
                                if (selected) setState(() => _selectedRole = 'Staff');
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (_selectedRole == 'Owner') ...[
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Mail ID',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Mail ID is required';
                            if (!val.contains('@')) return 'Enter a valid Mail ID';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _usernameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Restaurant / Owner Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_selectedRole == 'Staff') ...[
                        TextFormField(
                          controller: _usernameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Staff Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty ? 'Staff Name is required' : null,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _mobileCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Staff Mobile No.',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Mobile No. is required';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _ownerStoreEmailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Owner\'s Restaurant Mail ID',
                            prefixIcon: Icon(Icons.store_outlined),
                            hintText: 'e.g. owner@restaurant.com',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Owner\'s Mail ID is required';
                            if (!val.contains('@')) return 'Enter a valid Mail ID';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ] else ...[
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Login ID',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Login ID is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submitAuthForm(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (val) => val == null || val.length < 6
                          ? 'Password must be at least 6 characters' : null,
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitAuthForm,
                        child: _isLoading
                            ? const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                            : Text(
                          _isLoginMode ? 'LOGIN' : 'SIGN UP',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLoginMode = !_isLoginMode;
                          _formKey.currentState?.reset();
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                      ),
                      child: Text(
                        _isLoginMode
                            ? "Don't have an account? Sign Up"
                            : 'Already have an account? Login',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_isLoginMode)
                      TextButton(
                        onPressed: _resetPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                        ),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ============================================================================
// POS STATE PROVIDER — MVP persistence + counter safety
// ============================================================================
// ============================================================================
// POS STATE PROVIDER — tied to Mail ID
// ============================================================================
class PosProvider extends ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // We use the email to make the storage unique per user!
  String _currentUserEmail = '';

  StoreTemplate template = StoreTemplate();
  final FlutterTts flutterTts = FlutterTts();

  bool isSoundboxEnabled = false;
  bool isPrinterEnabled = false;
  bool isAutoUpdateCheckEnabled = true;
  bool isPrinterConnected = false;
  bool isOwnerDevice = true; // True = Owner Device (All bills synced), False = Staff Device (Today's bills)
  bool _ttsInitialized = false;
  bool _isLoaded = false;
  String connectedPrinterMac = '';
  String ownerPin = '1234';

  String get currentUserEmail => _currentUserEmail;

  //...THE PAGINATION STATE HERE <---
  DocumentSnapshot? _lastOrderDocument;
  bool _hasMoreOrders = true;
  bool _isFetchingMoreOrders = false;

  bool get isFetchingMoreOrders => _isFetchingMoreOrders;

  List<String> categories = [];
  List<MenuItem> _menu = [];
  List<ActiveBill> _activeBills = [];
  int _currentBillIndex = 0;
  int _nextTokenNumber = 2;
  int _billIdCounter = 1;
  List<CompletedOrder> _completedOrders = [];
  List<DayCloseRecord> _dayCloses = [];
  List<ExpenseRecord> _expenses = [];
  List<String> expenseCategories = [];

  PosProvider() {
    _initDefaults();
  }

  void _initDefaults() {
    categories = ['All', 'Tiffin', 'Drinks', 'Extras'];
    _menu = [
      MenuItem(id: '1', name: 'இட்லி', price: 12, category: 'Tiffin', imageUrl: 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=400'),
      MenuItem(id: '2', name: 'தோசை', price: 20, category: 'Tiffin', imageUrl: 'https://images.unsplash.com/photo-1668236543090-82eba5ee5976?w=400'),
      MenuItem(id: '3', name: 'சப்பாத்தி', price: 20, category: 'Tiffin', imageUrl: 'https://images.unsplash.com/photo-1626777552726-4a6b54c97e46?w=400'),
    ];
    _activeBills = [ActiveBill(id: '1', label: formatTokenLabel(1))];
    _currentBillIndex = 0;
    _nextTokenNumber = 2;
    _billIdCounter = 1;
    _completedOrders = [];
    _dayCloses = [];
    _expenses = [];
    expenseCategories = [
      'Vegetables', 'Grocery / Provisions', 'Milk / Dairy', 'Gas / LPG',
      'Oil', 'Eggs / Meat', 'Packaging', 'Wages', 'Electricity',
      'Rent', 'Transport', 'Repairs', 'Miscellaneous'
    ];
    template = StoreTemplate();
    isSoundboxEnabled = false;
    isPrinterEnabled = false;
    ownerPin = '1234';
  }

  StreamSubscription<DocumentSnapshot>? _restaurantSubscription;
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  StreamSubscription<QuerySnapshot>? _expensesSubscription;
  StreamSubscription<QuerySnapshot>? _closesSubscription;

  void _cancelSubscriptions() {
    _restaurantSubscription?.cancel();
    _ordersSubscription?.cancel();
    _expensesSubscription?.cancel();
    _closesSubscription?.cancel();
    _restaurantSubscription = null;
    _ordersSubscription = null;
    _expensesSubscription = null;
    _closesSubscription = null;
  }

  // --- NEW AUTHENTICATION METHODS ---
  Future<void> initDbConnection(String userEmail) async {
    final cleanEmail = userEmail.trim().toLowerCase();
    final isStaffAccount = cleanEmail.endsWith('@staff.pos');
    
    if (isStaffAccount) {
      final prefs = await SharedPreferences.getInstance();
      final savedOwnerEmail = prefs.getString('pos_user_email');
      if (savedOwnerEmail != null && savedOwnerEmail.isNotEmpty) {
        await login(savedOwnerEmail.trim().toLowerCase());
        return;
      }
    }
    
    await login(cleanEmail);
  }

  bool get isStaffUser {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    return userEmail.endsWith('@staff.pos');
  }

  bool get isOwner => !isStaffUser && isOwnerDevice;

  Future<void> login(String email) async {
    _currentUserEmail = email;
    try {
      final prefs = await SharedPreferences.getInstance();
      final isStaff = FirebaseAuth.instance.currentUser?.email?.endsWith('@staff.pos') ?? false;
      if (isStaff) {
        isOwnerDevice = false;
      } else {
        isOwnerDevice = prefs.getBool('is_owner_device_$_currentUserEmail') ?? true;
      }
    } catch (_) {
      isOwnerDevice = true;
    }
    await _loadState();
  }

  Future<void> setOwnerDeviceMode(bool isOwner) async {
    isOwnerDevice = isOwner;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_owner_device_$_currentUserEmail', isOwner);
    } catch (_) {}
    await _loadState();
  }

  Future<void> logout() async {
    _cancelSubscriptions();
    _isLoaded = false;
    _currentUserEmail = '';
    _initDefaults(); // Reset memory state to defaults for the next user
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    flutterTts.stop();
    super.dispose();
  }

  bool get isLoaded => _isLoaded;
  // ... (Keep the rest of your PosProvider methods exactly the same starting from `List<MenuItem> get menu => _menu;`)
  List<MenuItem> get menu => _menu;
  List<ActiveBill> get activeBills => _activeBills;
  ActiveBill get currentBill => _activeBills[_currentBillIndex];
  int get currentBillIndex => _currentBillIndex;
  List<CompletedOrder> get completedOrders => _completedOrders;
  List<DayCloseRecord> get dayCloses => _dayCloses;
  List<ExpenseRecord> get expenses => List.unmodifiable(_expenses);
  List<CartItem> get cartItems => currentBill.items.values.toList();
  int get totalItemCount => currentBill.totalCount;
  double get totalAmount => currentBill.totalAmount;

  int _inferNextTokenNumber() {
    var maxToken = 0;
    final digits = RegExp(r'\d+');
    for (final bill in _activeBills) {
      final match = digits.firstMatch(bill.label);
      final value = int.tryParse(match?.group(0) ?? '') ?? 0;
      if (value > maxToken) maxToken = value;
    }
    return maxToken + 1;
  }

  ActiveBill _createNextActiveBill({String orderType = 'DINE IN'}) {
    final tokenNumber = _nextTokenNumber++;
    return ActiveBill(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: formatTokenLabel(tokenNumber),
      orderType: orderType,
    );
  }

  Future<void> _loadState() async {
    if (_currentUserEmail.isEmpty) return;
    _cancelSubscriptions();

    try {
      final userDoc = _db.collection('restaurants').doc(_currentUserEmail);

      // 1. Real-time Subscription for Main Configuration Document
      _restaurantSubscription = userDoc.snapshots().listen((docSnapshot) {
        if (docSnapshot.exists && docSnapshot.data() != null) {
          final data = docSnapshot.data() as Map<String, dynamic>;
          categories = List<String>.from(data['categories'] as List? ?? categories);
          _menu = (data['menu'] as List? ?? []).map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          _activeBills = (data['activeBills'] as List? ?? []).map((e) => ActiveBill.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          if (_activeBills.isEmpty) _activeBills = [ActiveBill(id: '1', label: formatTokenLabel(1))];

          _currentBillIndex = (data['currentBillIndex'] as num?)?.toInt() ?? 0;
          if (_currentBillIndex >= _activeBills.length) {
            _currentBillIndex = _activeBills.isEmpty ? 0 : _activeBills.length - 1;
          }
          _billIdCounter = (data['billIdCounter'] as num?)?.toInt() ?? 1;
          _nextTokenNumber = (data['nextTokenNumber'] as num?)?.toInt() ?? _inferNextTokenNumber();
          expenseCategories = (data['expenseCategories'] as List? ?? []).map((e) => e.toString()).toList();
          isSoundboxEnabled = data['isSoundboxEnabled'] as bool? ?? false;
          isPrinterEnabled = data['isPrinterEnabled'] as bool? ?? false;
          isAutoUpdateCheckEnabled = data['isAutoUpdateCheckEnabled'] as bool? ?? true;
          connectedPrinterMac = data['connectedPrinterMac']?.toString() ?? '';
          ownerPin = data['ownerPin']?.toString() ?? '1234';
          if (data['template'] is Map) template.applyJson(Map<String, dynamic>.from(data['template']));
          _isLoaded = true;
          notifyListeners();
        }
      });

      // 2. Real-time Subscription for Completed Orders Subcollection
      Query<Map<String, dynamic>> ordersQuery = userDoc.collection('completedOrders');
      if (!isOwnerDevice) {
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        ordersQuery = ordersQuery.where('timestamp', isGreaterThanOrEqualTo: startOfToday.toIso8601String());
      }
      ordersQuery = ordersQuery.orderBy('timestamp', descending: true).limit(100);

      _ordersSubscription = ordersQuery.snapshots().listen((ordersSnap) {
        _completedOrders = ordersSnap.docs.map((d) => CompletedOrder.fromJson(d.data())).toList();
        if (ordersSnap.docs.isNotEmpty) {
          _lastOrderDocument = ordersSnap.docs.last;
        }
        _hasMoreOrders = ordersSnap.docs.length == 100;
        notifyListeners();
      });

      // 3. Real-time Subscription for Expenses Subcollection
      _expensesSubscription = userDoc.collection('expenses')
          .orderBy('timestamp', descending: true).limit(100).snapshots().listen((expensesSnap) {
        _expenses = expensesSnap.docs.map((d) => ExpenseRecord.fromJson(d.data())).toList();
        notifyListeners();
      });

      // 4. Real-time Subscription for Day Closes Subcollection
      _closesSubscription = userDoc.collection('dayCloses')
          .orderBy('timestamp', descending: true).limit(30).snapshots().listen((closesSnap) {
        _dayCloses = closesSnap.docs.map((d) => DayCloseRecord.fromJson(d.data())).toList();
        notifyListeners();
      });

    } catch (e) {
      debugPrint('Error loading Firestore stream: $e');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _saveState() async {
    if (!_isLoaded || _currentUserEmail.isEmpty) return;

    try {
      final data = {
        'categories': categories,
        'menu': _menu.map((e) => e.toJson()).toList(),
        'activeBills': _activeBills.map((e) => e.toJson()).toList(),
        'currentBillIndex': _currentBillIndex,
        'billIdCounter': _billIdCounter,
        'nextTokenNumber': _nextTokenNumber,
        'expenseCategories': expenseCategories,
        'isSoundboxEnabled': isSoundboxEnabled,
        'isPrinterEnabled': isPrinterEnabled,
        'isAutoUpdateCheckEnabled': isAutoUpdateCheckEnabled,
        'connectedPrinterMac': connectedPrinterMac,
        'ownerPin': ownerPin,
        'template': template.toJson(),
      };

      // SetOptions(merge: true) prevents overwriting subcollections
      await _db.collection('restaurants').doc(_currentUserEmail).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving main state: $e');
    }
  }

  Future<void> _initTts() async {
    if (_ttsInitialized) return;
    try {
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);
      await flutterTts.setSpeechRate(0.85);
      _ttsInitialized = true;
    } catch (_) {}
  }

  Future<void> setSoundboxEnabled(bool enabled) async {
    isSoundboxEnabled = enabled;
    notifyListeners();
    _saveState();
    if (!enabled) {
      try {
        await flutterTts.stop();
      } catch (_) {}
    } else {
      await _initTts();
    }
  }

  void setPrinterEnabled(bool enabled) {
    isPrinterEnabled = enabled;
    if (!enabled) {
      isPrinterConnected = false;
      connectedPrinterMac = '';
    }
    notifyListeners();
    _saveState();
  }

  void setAutoUpdateCheckEnabled(bool enabled) {
    isAutoUpdateCheckEnabled = enabled;
    notifyListeners();
    _saveState();
  }

  void setPrinterConnection(bool connected, {String mac = ''}) {
    isPrinterConnected = connected;
    if (connected && mac.isNotEmpty) {
      connectedPrinterMac = mac;
    }
    if (!connected) {
      connectedPrinterMac = '';
    }
    notifyListeners();
    _saveState();
  }

  bool verifyOwnerPin(String pin) => pin == ownerPin;

  void changeOwnerPin(String newPin) {
    if (newPin.length < 4) return;
    ownerPin = newPin;
    notifyListeners();
    _saveState();
  }

  int getItemQuantity(String itemId) =>
      currentBill.items[itemId]?.quantity ?? 0;

  void selectBill(int index) {
    if (index >= 0 && index < _activeBills.length) {
      _currentBillIndex = index;
      notifyListeners();
      _saveState();
    }
  }

  void setOrderType(String type) {
    if (type != 'DINE IN' && type != 'PARCEL') return;
    currentBill.orderType = type;
    notifyListeners();
    _saveState();
  }

  void holdAndCreateNewBill({String? label}) {
    final newBill = _createNextActiveBill();
    if (label != null && label.trim().isNotEmpty) {
      newBill.label = label.trim();
    }
    _activeBills.add(newBill);
    _currentBillIndex = _activeBills.length - 1;
    notifyListeners();
    _saveState();
  }

  void closeHeldBill(int index) {
    if (index < 0 || index >= _activeBills.length) return;
    if (_activeBills.length <= 1) {
      _activeBills[0] = _createNextActiveBill();
      _currentBillIndex = 0;
    } else {
      _activeBills.removeAt(index);
      if (_currentBillIndex > index) _currentBillIndex -= 1;
      if (_currentBillIndex >= _activeBills.length) {
        _currentBillIndex = _activeBills.length - 1;
      }
    }
    notifyListeners();
    _saveState();
  }

  void addToCart(MenuItem item) {
    if (!item.isAvailable) return;
    HapticFeedback.lightImpact();
    if (currentBill.items.containsKey(item.id)) {
      currentBill.items[item.id]!.quantity += 1;
    } else {
      currentBill.items[item.id] = CartItem(item: item.clone(), quantity: 1);
    }
    notifyListeners();
    _saveState();
  }

  void decrementQuantity(String itemId) {
    HapticFeedback.lightImpact();
    if (!currentBill.items.containsKey(itemId)) return;
    if (currentBill.items[itemId]!.quantity > 1) {
      currentBill.items[itemId]!.quantity -= 1;
    } else {
      currentBill.items.remove(itemId);
    }
    notifyListeners();
    _saveState();
  }

  void clearCurrentCart() {
    currentBill.items.clear();
    notifyListeners();
    _saveState();
  }

  CompletedOrder checkout({required String paymentMethod, double tenderAmount = 0.0, double changeAmount = 0.0}) {
    final clonedItems = currentBill.items.values.map((i) => i.clone()).toList();
    final order = CompletedOrder(
      billId: (_billIdCounter++).toString().padLeft(5, '0'),
      billLabel: currentBill.label,
      timestamp: DateTime.now(),
      items: clonedItems,
      totalAmount: currentBill.totalAmount,
      tenderAmount: tenderAmount,
      changeAmount: changeAmount,
      paymentMethod: paymentMethod,
      orderType: currentBill.orderType,
    );

    _completedOrders.insert(0, order);
    triggerSoundboxNotification(order.totalAmount, paymentMethod);

    // Save strictly to the Orders Subcollection
    _db.collection('restaurants').doc(_currentUserEmail)
        .collection('completedOrders').doc(order.billId)
        .set(order.toJson());

    if (_activeBills.length > 1) {
      _activeBills.removeAt(_currentBillIndex);
      _currentBillIndex = 0;
    } else {
      _activeBills[0] = _createNextActiveBill();
      _currentBillIndex = 0;
    }
    notifyListeners();
    _saveState(); // Saves the incremented bill counter
    return order;
  }

  void voidOrder(String billId, String reason) {
    final index = _completedOrders.indexWhere((o) => o.billId == billId);
    if (index == -1 || _completedOrders[index].isVoided) return;

    _completedOrders[index].isVoided = true;
    _completedOrders[index].voidReason = reason.trim().isEmpty ? 'Voided by owner' : reason.trim();
    _completedOrders[index].voidedAt = DateTime.now();

    // Update the specific document in the Subcollection
    _db.collection('restaurants').doc(_currentUserEmail)
        .collection('completedOrders').doc(billId)
        .update({
      'isVoided': true,
      'voidReason': _completedOrders[index].voidReason,
      'voidedAt': _completedOrders[index].voidedAt?.toIso8601String(),
    });

    notifyListeners();
  }

  void addExpense(ExpenseRecord record) {
    if (record.amount <= 0) return;
    _expenses.insert(0, record);

    _db.collection('restaurants').doc(_currentUserEmail)
        .collection('expenses').doc(record.id)
        .set(record.toJson());

    notifyListeners();
  }

  void updateExpense(ExpenseRecord updated) {
    final index = _expenses.indexWhere((e) => e.id == updated.id);
    if (index == -1 || updated.amount <= 0) return;
    _expenses[index] = updated;
    _expenses.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _db.collection('restaurants').doc(_currentUserEmail)
        .collection('expenses').doc(updated.id)
        .set(updated.toJson());

    notifyListeners();
  }

  void deleteExpense(String id) {
    _expenses.removeWhere((e) => e.id == id);

    _db.collection('restaurants').doc(_currentUserEmail)
        .collection('expenses').doc(id)
        .delete();

    notifyListeners();
  }

  bool addExpenseCategory(String category) {
    final clean = category.trim();
    if (clean.isEmpty) return false;
    if (expenseCategories.any((e) => e.toLowerCase() == clean.toLowerCase())) {
      return false;
    }
    expenseCategories.add(clean);
    notifyListeners();
    _saveState();
    return true;
  }

  List<ExpenseRecord> expensesBetween(DateTime start, DateTime end) {
    return _expenses
        .where((e) => !e.timestamp.isBefore(start) && !e.timestamp.isAfter(end))
        .toList();
  }

  double operatingExpensesBetween(DateTime start, DateTime end) {
    return expensesBetween(start, end)
        .where((e) => e.kind == 'EXPENSE')
        .fold<double>(0, (acc, e) => acc + e.amount);
  }

  double cashExpenseOutflowBetween(DateTime start, DateTime end) {
    return expensesBetween(start, end)
        .where((e) => e.kind == 'EXPENSE' && e.paymentMethod == 'CASH')
        .fold<double>(0, (acc, e) => acc + e.amount);
  }

  double ownerCashWithdrawalsBetween(DateTime start, DateTime end) {
    return expensesBetween(start, end)
        .where((e) => e.kind == 'OWNER WITHDRAWAL' && e.paymentMethod == 'CASH')
        .fold<double>(0, (acc, e) => acc + e.amount);
  }

  double cashAddedBetween(DateTime start, DateTime end) {
    return expensesBetween(start, end)
        .where((e) => e.kind == 'CASH ADDED' && e.paymentMethod == 'CASH')
        .fold<double>(0, (acc, e) => acc + e.amount);
  }

  void saveDayClose({
    required double expectedCash, required double countedCash, required double upiSales,
    required double totalSales, required int orderCount, double cashExpenses = 0,
    double ownerWithdrawals = 0, double cashAdded = 0, double operatingExpenses = 0,
  }) {
    final record = DayCloseRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      expectedCash: expectedCash, countedCash: countedCash,
      variance: countedCash - expectedCash, upiSales: upiSales,
      totalSales: totalSales, orderCount: orderCount,
      cashExpenses: cashExpenses, ownerWithdrawals: ownerWithdrawals,
      cashAdded: cashAdded, operatingExpenses: operatingExpenses,
    );

    _dayCloses.insert(0, record);

    _db.collection('restaurants').doc(_currentUserEmail)
        .collection('dayCloses').doc(record.id)
        .set(record.toJson());

    notifyListeners();
  }

  Future<void> loadMoreOrders() async {
    // Prevent overlapping fetches or fetching if we hit the end
    if (_isFetchingMoreOrders || !_hasMoreOrders || _lastOrderDocument == null || _currentUserEmail.isEmpty) return;

    _isFetchingMoreOrders = true;
    notifyListeners();

    try {
      final snap = await _db.collection('restaurants').doc(_currentUserEmail)
          .collection('completedOrders')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastOrderDocument!) // Start exactly after the last fetched bill
          .limit(100)
          .get();

      if (snap.docs.isNotEmpty) {
        final newOrders = snap.docs.map((d) => CompletedOrder.fromJson(d.data())).toList();
        _completedOrders.addAll(newOrders);
        _lastOrderDocument = snap.docs.last;
      }

      // If we got exactly 100, there might be more. If less, we hit the end of the database.
      _hasMoreOrders = snap.docs.length == 100;

    } catch (e) {
      debugPrint('Error fetching more orders: $e');
    } finally {
      _isFetchingMoreOrders = false;
      notifyListeners();
    }
  }

  Future<void> triggerSoundboxNotification(double amount, String method) async {
    if (!isSoundboxEnabled) return;
    await _initTts();
    final int amt = amount.toInt();
    try {
      if (template.soundboxLanguage == 'ta-IN') {
        await flutterTts.setLanguage('ta-IN');
        final speech = method == 'UPI'
            ? 'யூ பி ஐ மூலம் ரூபாய் $amt பெறப்பட்டது.'
            : 'ரொக்கம் ரூபாய் $amt பெறப்பட்டது.';
        await flutterTts.speak(speech);
      } else {
        await flutterTts.setLanguage('en-IN');
        final speech = method == 'UPI'
            ? 'Received $amt rupees on U P I.'
            : 'Received $amt rupees in cash.';
        await flutterTts.speak(speech);
      }
    } catch (_) {}
  }

  Future<bool> printThermalReceipt(CompletedOrder order) async {
    if (!isPrinterEnabled) return false;
    try {
      final bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) return false;
      final dateFormat = DateFormat('dd-MM-yyyy hh:mm a');
      final List<int> bytes = [];

      bytes.addAll([0x1B, 0x40]);
      bytes.addAll([0x1B, 0x61, 0x01]);
      bytes.addAll([0x1B, 0x45, 0x01]);
      bytes.addAll(latin1.encode('${template.storeName}\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);
      bytes.addAll(latin1.encode('${template.address}\n'));
      bytes.addAll(latin1.encode('Ph: ${template.phone}\n'));
      bytes.addAll(latin1.encode('--------------------------------\n'));
      bytes.addAll([0x1B, 0x61, 0x00]);
      bytes.addAll(
        latin1.encode('Bill: ${order.billId}  Pay: ${order.paymentMethod}\n'),
      );
      bytes.addAll(latin1.encode('Type: ${order.orderType}\n'));
      bytes.addAll(
        latin1.encode('Date: ${dateFormat.format(order.timestamp)}\n'),
      );
      bytes.addAll(latin1.encode('--------------------------------\n'));
      bytes.addAll(latin1.encode('Item            Qty   Rate   Amt\n'));
      bytes.addAll(latin1.encode('--------------------------------\n'));

      for (final cartItem in order.items) {
        final rawName = cartItem.item.name.padRight(15);
        final name = rawName
            .substring(0, rawName.length < 15 ? rawName.length : 15)
            .padRight(15);
        final qty = cartItem.quantity.toString().padLeft(3);
        final rate = cartItem.item.price.toInt().toString().padLeft(6);
        final total = cartItem.total.toInt().toString().padLeft(6);
        bytes.addAll(latin1.encode('$name $qty $rate $total\n'));
      }

      bytes.addAll(latin1.encode('--------------------------------\n'));
      bytes.addAll([0x1B, 0x45, 0x01]);
      final totalItems =
          'Total Items: ${order.items.fold<int>(0, (s, i) => s + i.quantity)}'
              .padRight(16);
      final totalAmount = 'Rs. ${order.totalAmount.toInt()}'.padLeft(14);
      bytes.addAll(latin1.encode('$totalItems$totalAmount\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);

      if (order.paymentMethod == 'CASH' && order.tenderAmount > 0) {
        bytes.addAll(
          latin1.encode('Cash Tendered: Rs. ${order.tenderAmount.toInt()}\n'),
        );
        bytes.addAll(
          latin1.encode('Change Returned: Rs. ${order.changeAmount.toInt()}\n'),
        );
      }
      if (order.isVoided) bytes.addAll(latin1.encode('*** VOIDED ***\n'));

      bytes.addAll(latin1.encode('--------------------------------\n'));
      bytes.addAll([0x1B, 0x61, 0x01]);
      bytes.addAll(latin1.encode('${template.footerMessage}\n'));
      bytes.addAll(latin1.encode('${template.subFooter}\n\n\n\n'));
      bytes.addAll([0x1D, 0x56, 0x41, 0x10]);
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  bool addCategory(String cat) {
    final clean = cat.trim();
    if (clean.isEmpty) return false;
    final exists = categories.any(
      (c) => c.toLowerCase() == clean.toLowerCase(),
    );
    if (exists) return false;
    categories.add(clean);
    notifyListeners();
    _saveState();
    return true;
  }

  bool editCategory(String oldCat, String newCat) {
    if (oldCat == 'All') return false;
    final clean = newCat.trim();
    final idx = categories.indexOf(oldCat);
    if (idx == -1 || clean.isEmpty) return false;
    final duplicate = categories.any(
      (c) => c != oldCat && c.toLowerCase() == clean.toLowerCase(),
    );
    if (duplicate) return false;

    categories[idx] = clean;
    for (final item in _menu) {
      if (item.category == oldCat) item.category = clean;
    }
    notifyListeners();
    _saveState();
    return true;
  }

  bool deleteCategory(String cat) {
    if (cat == 'All') return false;
    if (_menu.any((item) => item.category == cat)) return false;
    final removed = categories.remove(cat);
    if (removed) {
      notifyListeners();
      _saveState();
    }
    return removed;
  }

  void addMenuItem(MenuItem item) {
    _menu.add(item);
    notifyListeners();
    _saveState();
  }

  void updateMenuItem(
    String id,
    String name,
    double price,
    String category,
    String imageUrl,
  ) {
    final index = _menu.indexWhere((m) => m.id == id);
    if (index != -1) {
      _menu[index].name = name;
      _menu[index].price = price;
      _menu[index].category = category;
      _menu[index].imageUrl = imageUrl;
      notifyListeners();
      _saveState();
    }
  }

  void setMenuAvailability(String id, bool available) {
    final index = _menu.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _menu[index].isAvailable = available;
    notifyListeners();
    _saveState();
  }

  void deleteMenuItem(String id) {
    _menu.removeWhere((m) => m.id == id);
    notifyListeners();
    _saveState();
  }

  void updateTemplate({
    required String storeName,
    required String tagline,
    required String address,
    required String phone,
    required List<String> upiIds,
    required String footer,
    required String soundboxLang,
    String? logoDataUrl,
  }) {
    template.storeName = storeName;
    template.tagline = tagline;
    template.address = address;
    template.phone = phone;
    template.upiIds = upiIds.where((s) => s.trim().isNotEmpty).toList();
    if (template.upiIds.isEmpty) template.upiIds = ['friendstiffin@okaxis'];
    template.footerMessage = footer;
    template.soundboxLanguage = soundboxLang;
    if (logoDataUrl != null) template.logoDataUrl = logoDataUrl;
    notifyListeners();
    _saveState();
  }
}

// ============================================================================
// MAIN APP SHELL
// ============================================================================
class FriendsTiffinApp extends StatelessWidget {
  const FriendsTiffinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Friends Tiffin Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: AppTheme.surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.primary,
          primary: AppTheme.primary,
          secondary: AppTheme.accent,
          surface: AppTheme.surface,
          error: AppTheme.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        dividerColor: AppTheme.border,
        cardTheme: const CardThemeData(
          color: AppTheme.cardBg,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      home: const AuthGate(), // Updated from DashboardScreen()
    );
  }
}// ============================================================================

// SCREEN 1: MODERN DASHBOARD / COUNTER HUB
// ============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _checkedForUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pos = Provider.of<PosProvider>(context, listen: false);
      if (!_checkedForUpdate && mounted && pos.isAutoUpdateCheckEnabled) {
        _checkedForUpdate = true;
        checkAppUpdate(context, showNoUpdateDialog: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    if (!pos.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    final todayOrders = pos.completedOrders.where(
      (o) =>
          !o.isVoided &&
          o.timestamp.year == now.year &&
          o.timestamp.month == now.month &&
          o.timestamp.day == now.day,
    );
    final todayGross = todayOrders.fold<double>(
      0.0,
      (s, o) => s + o.totalAmount,
    );
    final todayCash = todayOrders
        .where((o) => o.paymentMethod == 'CASH')
        .fold<double>(0.0, (s, o) => s + o.totalAmount);
    final todayUpi = todayOrders
        .where((o) => o.paymentMethod == 'UPI')
        .fold<double>(0.0, (s, o) => s + o.totalAmount);
    final orderCount = todayOrders.length;
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final todayExpenses = pos.operatingExpensesBetween(todayStart, todayEnd);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                children: [
                  _heroHeader(
                    context,
                    pos,
                    todayGross: todayGross,
                    todayCash: todayCash,
                    todayUpi: todayUpi,
                    orderCount: orderCount,
                  ),
                  const SizedBox(height: 16),
                  _quickActions(context),
                  const SizedBox(height: 16),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final desktop = constraints.maxWidth >= 900;
                        if (desktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _activeBillsPanel(context, pos),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: _counterSnapshot(
                                  context,
                                  pos,
                                  todayCash: todayCash,
                                  todayUpi: todayUpi,
                                  orderCount: orderCount,
                                  todayExpenses: todayExpenses,
                                ),
                              ),
                            ],
                          );
                        }
                        return _activeBillsPanel(context, pos);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _primaryBillingButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroHeader(
    BuildContext context,
    PosProvider pos, {
    required double todayGross,
    required double todayCash,
    required double todayUpi,
    required int orderCount,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName ?? (pos.isOwnerDevice ? 'Owner' : 'Staff');

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Container(
          padding: EdgeInsets.all(compact ? 18 : 24),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            boxShadow: AppTheme.elevationCard,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: pos.template.logoDataUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AppMenuImage(
                              source: pos.template.logoDataUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          )
                        : const Icon(
                            Icons.restaurant_menu_rounded,
                            color: AppTheme.accent,
                            size: 25,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          pos.template.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 17 : 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          pos.template.tagline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    _headerStatus(
                      !pos.isPrinterEnabled
                          ? 'Printer off'
                          : (pos.isPrinterConnected
                                ? 'Printer ready'
                                : 'Printer offline'),
                      !pos.isPrinterEnabled
                          ? Icons.print_disabled_rounded
                          : (pos.isPrinterConnected
                                ? Icons.print_rounded
                                : Icons.print_outlined),
                      pos.isPrinterEnabled && pos.isPrinterConnected
                          ? AppTheme.success
                          : Colors.white70,
                    ),
                    const SizedBox(width: 10),
                  ],
                  IconButton(
                    tooltip: 'Account & Settings',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.settings_outlined, size: 21),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: AppTheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (ctx) => _buildProfileMenu(ctx, userName),
                      );
                    },
                  ),
                ],
              ),
              SizedBox(height: compact ? 18 : 24),
              if (compact)
                Column(
                  children: [
                    _turnoverCard(todayGross),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _heroMetric(
                            'Cash',
                            todayCash,
                            Icons.payments_outlined,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _heroMetric(
                            'UPI',
                            todayUpi,
                            Icons.qr_code_2_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(flex: 2, child: _turnoverCard(todayGross)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _heroMetric(
                        'Cash',
                        todayCash,
                        Icons.payments_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _heroMetric(
                        'UPI',
                        todayUpi,
                        Icons.qr_code_2_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _heroMetric(
                        'Orders',
                        orderCount.toDouble(),
                        Icons.receipt_long_outlined,
                        isMoney: false,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildProfileMenu(BuildContext context, String userName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: AppTheme.primaryMuted,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, size: 32, color: AppTheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            userName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            FirebaseAuth.instance.currentUser?.email ?? '',
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_rounded, color: AppTheme.textPrimary),
            title: const Text('Store Settings', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context); // Close bottom sheet
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MainSettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppTheme.error),
            title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.error)),
            onTap: () async {
              Navigator.pop(context); // Close bottom sheet
              await FirebaseAuth.instance.signOut();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _turnoverCard(double amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: AppTheme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "TODAY'S TURNOVER",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₹${amount.toInt()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(
    String label,
    double value,
    IconData icon, {
    bool isMoney = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isMoney ? '₹${value.toInt()}' : '${value.toInt()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStatus(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final pos = Provider.of<PosProvider>(context, listen: false);
    final isStaff = pos.isStaffUser;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final actions = [
          _ActionSpec(
            title: 'New Bill',
            subtitle: 'Start billing',
            icon: Icons.point_of_sale_rounded,
            color: AppTheme.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillingGridScreen()),
            ),
          ),
          _ActionSpec(
            title: 'Reports',
            subtitle: 'Sales insights',
            icon: Icons.insights_rounded,
            color: AppTheme.info,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),
          if (!isStaff)
            _ActionSpec(
              title: 'Expenses',
              subtitle: 'செலவு & cash',
              icon: Icons.receipt_long_rounded,
              color: AppTheme.error,
              onTap: () async {
                final approved = await requestOwnerPin(
                  context,
                  pos,
                  title: 'Expenses & Cash Movements',
                );
                if (!approved || !context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpensesScreen()),
                );
              },
            ),
          _ActionSpec(
            title: 'Cash Drawer',
            subtitle: 'கல்லா கணக்கு',
            icon: Icons.account_balance_wallet_outlined,
            color: AppTheme.accentDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DenominationScreen()),
            ),
          ),
        ];

        if (compact) {
          final cardWidth = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions
                .map(
                  (a) => SizedBox(
                    width: cardWidth,
                    child: _actionCard(a, compact: true),
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: actions
              .map(
                (a) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: a == actions.last ? 0 : 12),
                    child: _actionCard(a),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _actionCard(_ActionSpec action, {bool compact = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 15,
            vertical: compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.elevationLow,
          ),
          child: compact
              ? Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: action.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(action.icon, color: action.color, size: 19),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: action.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(action.icon, color: action.color, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            action.subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _activeBillsPanel(BuildContext context, PosProvider pos) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.elevationLow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryMuted,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppTheme.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active orders',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Held dining tokens and open bills',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryMuted,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${pos.activeBills.length} ACTIVE',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: pos.activeBills.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final bill = pos.activeBills[idx];
                final current = idx == pos.currentBillIndex;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () {
                      pos.selectBill(idx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BillingGridScreen(),
                        ),
                      );
                    },
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: current
                            ? AppTheme.primaryMuted.withValues(alpha: 0.70)
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: current
                              ? AppTheme.primary.withValues(alpha: 0.25)
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: current ? AppTheme.primary : Colors.white,
                              borderRadius: BorderRadius.circular(13),
                              border: current
                                  ? null
                                  : Border.all(color: AppTheme.border),
                            ),
                            child: Icon(
                              Icons.receipt_outlined,
                              color: current
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        bill.label,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (current) ...[
                                      const SizedBox(width: 7),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Text(
                                          'CURRENT',
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w900,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${bill.totalCount} items · ${bill.orderType}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${bill.totalAmount.toInt()}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'OPEN →',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _counterSnapshot(
    BuildContext context,
    PosProvider pos, {
    required double todayCash,
    required double todayUpi,
    required int orderCount,
    required double todayExpenses,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.elevationLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Counter snapshot',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Live operational summary',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 18),
          _snapshotRow(
            Icons.payments_outlined,
            'Cash sales',
            '₹${todayCash.toInt()}',
            AppTheme.primary,
          ),
          const SizedBox(height: 10),
          _snapshotRow(
            Icons.qr_code_2_rounded,
            'UPI sales',
            '₹${todayUpi.toInt()}',
            AppTheme.info,
          ),
          const SizedBox(height: 10),
          _snapshotRow(
            Icons.shopping_bag_outlined,
            'Expenses today',
            '₹${todayExpenses.toInt()}',
            AppTheme.error,
          ),
          const SizedBox(height: 10),
          _snapshotRow(
            Icons.receipt_long_outlined,
            'Orders today',
            '$orderCount',
            AppTheme.accentDark,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: pos.isPrinterEnabled && pos.isPrinterConnected
                  ? const Color(0xFFF0FDF4)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: pos.isPrinterEnabled && pos.isPrinterConnected
                    ? const Color(0xFFBBF7D0)
                    : AppTheme.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  !pos.isPrinterEnabled
                      ? Icons.power_settings_new_rounded
                      : (pos.isPrinterConnected
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded),
                  color: pos.isPrinterEnabled && pos.isPrinterConnected
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !pos.isPrinterEnabled
                            ? 'Printer turned off'
                            : (pos.isPrinterConnected
                                  ? 'Printer connected'
                                  : 'Printer not connected'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        !pos.isPrinterEnabled
                            ? 'Enable it only when you need printed receipts'
                            : (pos.isPrinterConnected
                                  ? 'Ready for thermal receipts'
                                  : 'Configure it from Settings'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _snapshotRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryBillingButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BillingGridScreen()),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.point_of_sale_rounded, size: 22),
            SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'OPEN BILLING COUNTER',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ActionSpec {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionSpec({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

// ============================================================================
// SCREEN 2: ERGONOMIC BILLING GRID WITH DUAL-DECK TRAY
// ============================================================================
class BillingGridScreen extends StatefulWidget {
  const BillingGridScreen({super.key});
  @override
  State<BillingGridScreen> createState() => _BillingGridScreenState();
}

class _BillingGridScreenState extends State<BillingGridScreen> {
  String _selectedCategory = 'All';
  final ScrollController _tokenRailController = ScrollController();

  @override
  void dispose() {
    _tokenRailController.dispose();
    super.dispose();
  }

  String _shortTokenLabel(ActiveBill bill, int fallbackIndex) {
    final match = RegExp(r'\d+').firstMatch(bill.label);
    final number = int.tryParse(match?.group(0) ?? '') ?? (fallbackIndex + 1);
    return 'T$number';
  }

  void _selectToken(PosProvider pos, int index) {
    if (index == pos.currentBillIndex) return;
    HapticFeedback.selectionClick();
    pos.selectBill(index);
  }

  void _createToken(PosProvider pos) {
    // Avoid accumulating empty tokens. If the current token is already empty,
    // the cashier can simply start using it.
    if (pos.currentBill.items.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Current token is empty — start adding items here.'),
            duration: Duration(milliseconds: 1400),
          ),
        );
      return;
    }

    HapticFeedback.lightImpact();
    pos.holdAndCreateNewBill();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tokenRailController.hasClients) return;
      _tokenRailController.animateTo(
        _tokenRailController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final filteredItems = _selectedCategory == 'All'
        ? pos.menu
        : pos.menu.where((i) => i.category == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(
          children: [
            Icon(Icons.point_of_sale_rounded, size: 20, color: AppTheme.accent),
            SizedBox(width: 8),
            Text(
              'Billing Counter',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _openTokenRail(pos),
            const Divider(height: 1, color: Color(0xFFE2E8E4)),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  const Text(
                    'Order type',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _orderTypeButton(
                            label: 'DINE IN',
                            icon: Icons.restaurant_rounded,
                            selected: pos.currentBill.orderType == 'DINE IN',
                            onTap: () => pos.setOrderType('DINE IN'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _orderTypeButton(
                            label: 'PARCEL',
                            icon: Icons.shopping_bag_outlined,
                            selected: pos.currentBill.orderType == 'PARCEL',
                            onTap: () => pos.setOrderType('PARCEL'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8E4)),
            // Category Slider (Horizontal Pill Rail)
            Container(
              height: 52,
              color: Colors.white,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: pos.categories.length,
                itemBuilder: (context, idx) {
                  final cat = pos.categories[idx];
                  final isSelected = _selectedCategory == cat;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      selected: isSelected,
                      showCheckmark: false,
                      label: Text(cat),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w900
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                      backgroundColor: Colors.grey.shade100,
                      selectedColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? AppTheme.primary
                              : Colors.grey.shade300,
                        ),
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE2E8E4)),

            // Responsive food catalog grid. Card height is calculated from the
            // available width so the selected quantity controls never overflow on
            // small phones, browser zoom, or slightly larger text metrics.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final int columns = width >= 1180
                      ? 6
                      : width >= 900
                      ? 5
                      : width >= 650
                      ? 4
                      : width < 360
                      ? 2
                      : 3;
                  const horizontalPadding =
                      20.0; // GridView 10px on both sides.
                  const spacing = 12.0;
                  final usableWidth =
                      (width - horizontalPadding - (columns - 1) * spacing)
                          .clamp(120.0, double.infinity);
                  final itemWidth = usableWidth / columns;
                  final desiredHeight = itemWidth < 125
                      ? 198.0
                      : itemWidth < 150
                      ? 210.0
                      : itemWidth < 190
                      ? 224.0
                      : 238.0;
                  final aspectRatio = (itemWidth / desiredHeight)
                      .clamp(0.52, 0.84)
                      .toDouble();

                  return GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: aspectRatio,
                    ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final qty = pos.getItemQuantity(item.id);
                      final isAdded = qty > 0;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        padding: EdgeInsets.all(isAdded ? 3.0 : 1.0),
                        decoration: BoxDecoration(
                          color: isAdded
                              ? AppTheme.primary
                              : (!item.isAvailable
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: isAdded
                              ? AppTheme.elevationCard
                              : AppTheme.elevationLow,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            isAdded ? 13 : 15,
                          ),
                          child: Material(
                            color: isAdded
                                ? const Color(0xFFF5FAF7)
                                : Colors.white,
                            child: InkWell(
                              onTap: item.isAvailable
                                  ? () => pos.addToCart(item)
                                  : null,
                              child: Stack(
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            AppMenuImage(
                                              source: item.imageUrl,
                                              fit: BoxFit.cover,
                                              color: item.isAvailable
                                                  ? null
                                                  : Colors.white.withValues(
                                                      alpha: 0.58,
                                                    ),
                                              colorBlendMode: item.isAvailable
                                                  ? null
                                                  : BlendMode.srcOver,
                                              fallback: Container(
                                                color: Colors.grey.shade200,
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.fastfood,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                            if (isAdded)
                                              Container(
                                                color: AppTheme.primary
                                                    .withValues(alpha: 0.10),
                                              ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        height: 54,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            5,
                                            8,
                                            5,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                item.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                  color: isAdded
                                                      ? AppTheme.primary
                                                      : AppTheme.textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  '₹${item.price.toInt()}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 14,
                                                    color: AppTheme.accentDark,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isAdded)
                                        SizedBox(
                                          height: 48,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryMuted,
                                              border: Border(
                                                top: BorderSide(
                                                  color: AppTheme.primary
                                                      .withValues(alpha: 0.18),
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                _foodQtyButton(
                                                  icon: Icons.remove_rounded,
                                                  foreground: AppTheme.error,
                                                  background: Colors.white,
                                                  onTap: () =>
                                                      pos.decrementQuantity(
                                                        item.id,
                                                      ),
                                                ),
                                                const SizedBox(width: 3),
                                                Expanded(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                          '$qty × ₹${item.price.toInt()}',
                                                          maxLines: 1,
                                                          style: const TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: AppTheme
                                                                .textSecondary,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 1),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Text(
                                                          '₹${(qty * item.price).toInt()}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 15,
                                                                height: 1,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                color: AppTheme
                                                                    .primary,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 3),
                                                _foodQtyButton(
                                                  icon: Icons.add_rounded,
                                                  foreground: Colors.white,
                                                  background: AppTheme.primary,
                                                  onTap: item.isAvailable
                                                      ? () =>
                                                            pos.addToCart(item)
                                                      : null,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (!item.isAvailable)
                                    Positioned(
                                      top: 7,
                                      left: 7,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.error,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: const Text(
                                          'SOLD OUT',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (isAdded) ...[
                                    Positioned(
                                      top: 7,
                                      left: 7,
                                      child: Container(
                                        width: 27,
                                        height: 27,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppTheme.primary,
                                            width: 1.5,
                                          ),
                                          boxShadow: AppTheme.elevationLow,
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 7,
                                      right: 7,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 46,
                                          maxWidth: 78,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.18,
                                              ),
                                              blurRadius: 5,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'QTY $qty',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 11,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Persistent Live Order Deck (Mini Running Tray)
            if (pos.cartItems.isNotEmpty)
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: pos.cartItems.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final item = pos.cartItems[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            item.item.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '×${item.quantity}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // High-contrast checkout bar with a compact narrow-phone mode.
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 390;
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(10),
                        ),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppTheme.error,
                        ),
                        onPressed: pos.cartItems.isEmpty
                            ? null
                            : pos.clearCurrentCart,
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 12 : 18,
                              ),
                            ),
                            onPressed: pos.cartItems.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const CartCheckoutScreen(),
                                    ),
                                  ),
                            child: Row(
                              children: [
                                if (!compact) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${pos.totalItemCount} ITEMS',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    compact
                                        ? '${pos.totalItemCount} items'
                                        : 'Proceed',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 13 : 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '₹${pos.totalAmount.toInt()} ➔',
                                    style: TextStyle(
                                      fontSize: compact ? 18 : 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _openTokenRail(PosProvider pos) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'OPEN TOKENS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${pos.activeBills.length} open',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 54,
            child: ListView.separated(
              controller: _tokenRailController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(),
              itemCount: pos.activeBills.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                if (index == pos.activeBills.length) {
                  return Tooltip(
                    message: 'New token',
                    child: Material(
                      color: AppTheme.accentLight,
                      shape: CircleBorder(
                        side: BorderSide(
                          color: AppTheme.accent.withValues(alpha: 0.55),
                          width: 1.5,
                        ),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _createToken(pos),
                        child: const SizedBox(
                          width: 50,
                          height: 50,
                          child: Icon(
                            Icons.add_rounded,
                            color: AppTheme.accent,
                            size: 27,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final bill = pos.activeBills[index];
                final selected = index == pos.currentBillIndex;
                final itemCount = bill.totalCount;

                return Tooltip(
                  message:
                      '${bill.label} • ${bill.orderType} • $itemCount items • ₹${bill.totalAmount.toInt()}',
                  child: GestureDetector(
                    onTap: () => _selectToken(pos, index),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          width: 50,
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? AppTheme.primary
                                : itemCount > 0
                                ? AppTheme.primaryMuted
                                : AppTheme.surface,
                            border: Border.all(
                              color: selected
                                  ? AppTheme.accent
                                  : itemCount > 0
                                  ? AppTheme.primaryLight
                                  : AppTheme.border,
                              width: selected ? 2.5 : 1.4,
                            ),
                            boxShadow: selected
                                ? AppTheme.elevationLow
                                : const <BoxShadow>[],
                          ),
                          child: Text(
                            _shortTokenLabel(bill, index),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: selected ? Colors.white : AppTheme.primary,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (itemCount > 0)
                          Positioned(
                            right: -3,
                            top: -3,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 19,
                                minHeight: 19,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.accent
                                    : AppTheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                itemCount > 99 ? '99+' : '$itemCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _foodQtyButton({
    required IconData icon,
    required Color foreground,
    required Color background,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      elevation: background == Colors.white ? 1 : 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 19, color: foreground),
        ),
      ),
    );
  }

  Widget _orderTypeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppTheme.primary : AppTheme.surface,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} // ============================================================================

// SCREEN 3: CART CHECKOUT & DIRECT CASH CHANGE CALCULATOR
// ============================================================================
class CartCheckoutScreen extends StatelessWidget {
  const CartCheckoutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('${pos.currentBill.label} • ${pos.currentBill.orderType}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: pos.cartItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final cartItem = pos.cartItems[index];

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppTheme.elevationLow,
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 410;
                        final title = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cartItem.item.name,
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹${cartItem.item.price.toInt()} each',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                        final stepper = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              iconSize: 22,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              icon: const Icon(
                                Icons.remove_circle,
                                color: AppTheme.error,
                              ),
                              onPressed: () =>
                                  pos.decrementQuantity(cartItem.item.id),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                '${cartItem.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              iconSize: 22,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              icon: const Icon(
                                Icons.add_circle,
                                color: AppTheme.primary,
                              ),
                              onPressed: () => pos.addToCart(cartItem.item),
                            ),
                          ],
                        );
                        final amount = Text(
                          '₹${cartItem.total.toInt()}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        );

                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              title,
                              const SizedBox(height: 9),
                              Row(
                                children: [
                                  stepper,
                                  const Spacer(),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: amount,
                                  ),
                                ],
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(flex: 3, child: title),
                            stepper,
                            const SizedBox(width: 14),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: amount,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: AppTheme.elevationFloat,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total Payable (${pos.totalItemCount} Items)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '₹${pos.totalAmount.toInt()}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stackButtons = constraints.maxWidth < 410;
                      Widget cashButton() => ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 12,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () =>
                            _openCashCalculatorDialog(context, pos),
                        icon: const Icon(Icons.money),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'CASH ₹${pos.totalAmount.toInt()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                      Widget upiButton() => ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0277BD),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 12,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  UpiPaymentScreen(amount: pos.totalAmount),
                            ),
                          );
                        },
                        icon: const Icon(Icons.qr_code_2),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'UPI ₹${pos.totalAmount.toInt()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );

                      if (stackButtons) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            cashButton(),
                            const SizedBox(height: 10),
                            upiButton(),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: cashButton()),
                          const SizedBox(width: 12),
                          Expanded(child: upiButton()),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCashCalculatorDialog(
    BuildContext context,
    PosProvider pos,
  ) async {
    final result = await showDialog<_CashSettlementResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CashSettlementDialog(billTotal: pos.totalAmount),
    );
    if (result == null || !context.mounted) return;

    final order = pos.checkout(
      paymentMethod: 'CASH',
      tenderAmount: result.tender,
      changeAmount: result.change,
    );
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => PaymentSuccessScreen(order: order)),
    );
  }
}

class _CashSettlementResult {
  final double tender;
  final double change;

  const _CashSettlementResult({required this.tender, required this.change});
}

class _CashSettlementDialog extends StatefulWidget {
  final double billTotal;

  const _CashSettlementDialog({required this.billTotal});

  @override
  State<_CashSettlementDialog> createState() => _CashSettlementDialogState();
}

class _CashSettlementDialogState extends State<_CashSettlementDialog> {
  late final TextEditingController _controller;
  late double _tender;

  double get _change =>
      _tender > widget.billTotal ? _tender - widget.billTotal : 0.0;
  bool get _canConfirm => _tender >= widget.billTotal;

  @override
  void initState() {
    super.initState();
    _tender = widget.billTotal;
    _controller = TextEditingController(
      text: widget.billTotal.toStringAsFixed(widget.billTotal % 1 == 0 ? 0 : 2),
    );
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setTender(double amount) {
    setState(() {
      _tender = amount;
      _controller.text = amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2);
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  void _confirm() {
    if (!_canConfirm) return;
    Navigator.of(
      context,
    ).pop(_CashSettlementResult(tender: _tender, change: _change));
  }

  @override
  Widget build(BuildContext context) {
    final belowDue = _tender < widget.billTotal;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Cash Settlement',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bill due',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '₹${widget.billTotal.toStringAsFixed(widget.billTotal % 1 == 0 ? 0 : 2)}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                decoration: InputDecoration(
                  labelText: 'Cash received (வாங்கிய பணம்)',
                  prefixText: '₹ ',
                  errorText: belowDue
                      ? 'Cash received is less than the bill amount'
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onChanged: (value) => setState(
                  () => _tender = double.tryParse(value.trim()) ?? 0.0,
                ),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Exact'),
                    onPressed: () => _setTender(widget.billTotal),
                  ),
                  ActionChip(
                    label: const Text('₹100'),
                    onPressed: () => _setTender(100),
                  ),
                  ActionChip(
                    label: const Text('₹200'),
                    onPressed: () => _setTender(200),
                  ),
                  ActionChip(
                    label: const Text('₹500'),
                    onPressed: () => _setTender(500),
                  ),
                  ActionChip(
                    label: const Text('₹1000'),
                    onPressed: () => _setTender(1000),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accentLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Change to return\n(திருப்பித் தர வேண்டியது)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '₹${_change.toStringAsFixed(_change % 1 == 0 ? 0 : 2)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _canConfirm ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text(
                  'CONFIRM CASH PAYMENT',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 4: INTENT UPI QR GENERATOR
// ============================================================================
class UpiPaymentScreen extends StatefulWidget {
  final double amount;
  const UpiPaymentScreen({super.key, required this.amount});

  @override
  State<UpiPaymentScreen> createState() => _UpiPaymentScreenState();
}

class _UpiPaymentScreenState extends State<UpiPaymentScreen> {
  int selectedUpiIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final upiIds = pos.template.upiIds.isNotEmpty ? pos.template.upiIds : ['friendstiffin@okaxis'];
    if (selectedUpiIndex >= upiIds.length) {
      selectedUpiIndex = 0;
    }
    final vpa = upiIds[selectedUpiIndex];
    final payeeName = pos.template.storeName;
    final upiUri =
        'upi://pay?pa=$vpa&pn=${Uri.encodeComponent(payeeName)}&am=${widget.amount}&cu=INR';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('UPI Smart Pay')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final qrSize = constraints.maxWidth < 340 ? 190.0 : 220.0;
            final minHeight = constraints.maxHeight > 48
                ? constraints.maxHeight - 48
                : 0.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'SCAN & PAY',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '₹${widget.amount.toInt()}',
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    if (upiIds.length > 1) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Select Receiving UPI ID / QR:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: upiIds.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final id = entry.value;
                          final isSelected = idx == selectedUpiIndex;
                          return ChoiceChip(
                            label: Text(id),
                            selected: isSelected,
                            onSelected: (_) => setState(() => selectedUpiIndex = idx),
                            selectedColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppTheme.elevationCard,
                      ),
                      child: QrImageView(
                        data: upiUri,
                        version: QrVersions.auto,
                        size: qrSize,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      pos.template.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      vpa,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          final order = Provider.of<PosProvider>(
                            context,
                            listen: false,
                          ).checkout(paymentMethod: 'UPI');
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PaymentSuccessScreen(order: order),
                            ),
                          );
                        },
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'CONFIRM PAYMENT RECEIVED',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel Transaction',
                        style: TextStyle(color: AppTheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 5: ORDER SUCCESS & INSTANT BILLING RETURN
// ============================================================================
class PaymentSuccessScreen extends StatelessWidget {
  final CompletedOrder order;
  const PaymentSuccessScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context, listen: false);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight > 48
                    ? constraints.maxHeight - 48
                    : 0.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryMuted,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 64,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Payment Confirmed!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '₹${order.totalAmount.toInt()}',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    '${order.orderType} • ${order.paymentMethod} • ${order.billLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  if (order.paymentMethod == 'CASH' && order.changeAmount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Change Given: ₹${order.changeAmount.toInt()} (சில்லறை)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.accent,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Thank you! / நன்றி!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (pos.isPrinterEnabled) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          final ok = await pos.printThermalReceipt(order);
                          if (!ok && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BillReceiptScreen(order: order),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.print),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'PRINT RECEIPT (பில் அச்சிடு)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BillReceiptScreen(order: order),
                        ),
                      ),
                      icon: const Icon(Icons.preview),
                      label: const Text('View Bill on Screen'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.popUntil(context, (route) => route.isFirst);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BillingGridScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'NEXT CUSTOMER (அடுத்த பில்)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 6: PAPER-STYLE DIGITAL THERMAL RECEIPT
// ============================================================================
class BillReceiptScreen extends StatelessWidget {
  final CompletedOrder order;
  const BillReceiptScreen({super.key, required this.order});
  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final template = pos.template;
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        title: const Text('Bill Preview'),
        actions: [
          IconButton(
            tooltip: pos.isPrinterEnabled
                ? 'Print receipt'
                : 'Printer is turned off',
            icon: Icon(
              pos.isPrinterEnabled ? Icons.print : Icons.print_disabled,
            ),
            onPressed: pos.isPrinterEnabled
                ? () => pos.printThermalReceipt(order)
                : null,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: constraints.maxWidth < 360
                  ? (constraints.maxWidth > 32
                        ? constraints.maxWidth - 32
                        : constraints.maxWidth)
                  : 320,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: AppTheme.elevationCard,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    template.storeName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template.address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    'Ph: ${template.phone}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  const Divider(thickness: 1),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Bill: ${order.billId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          dateFormat.format(order.timestamp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${order.orderType} • ${order.paymentMethod}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  const Divider(thickness: 1),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Item',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Qty x Rate',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Amount',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...order.items.map(
                    (cartItem) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              cartItem.item.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${cartItem.quantity} x ${cartItem.item.price.toInt()}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '₹${cartItem.total.toInt()}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(thickness: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Items:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${order.items.fold<int>(0, (s, i) => s + i.quantity)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Amount:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '₹${order.totalAmount.toInt()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  if (order.paymentMethod == 'CASH' &&
                      order.tenderAmount > 0) ...[
                    const Divider(thickness: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Cash Tendered:',
                          style: TextStyle(fontSize: 11),
                        ),
                        Text(
                          '₹${order.tenderAmount.toInt()}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Change Returned:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '₹${order.changeAmount.toInt()}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (order.isVoided) ...[
                    const Divider(thickness: 1),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      color: const Color(0xFFFFEBEE),
                      child: Column(
                        children: [
                          const Text(
                            'VOIDED BILL',
                            style: TextStyle(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          if (order.voidReason.isNotEmpty)
                            Text(
                              order.voidReason,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.error,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(thickness: 1),
                  Text(
                    template.footerMessage,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    template.subFooter,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} // ============================================================================

// OWNER PIN GATE — simple MVP protection for sensitive actions
// ============================================================================
Future<bool> requestOwnerPin(
  BuildContext context,
  PosProvider pos, {
  String title = 'Owner approval',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _OwnerPinDialog(title: title, verifyPin: pos.verifyOwnerPin),
  );
  return result ?? false;
}

class _OwnerPinDialog extends StatefulWidget {
  final String title;
  final bool Function(String pin) verifyPin;

  const _OwnerPinDialog({required this.title, required this.verifyPin});

  @override
  State<_OwnerPinDialog> createState() => _OwnerPinDialogState();
}

class _OwnerPinDialogState extends State<_OwnerPinDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your owner PIN');
      return;
    }
    if (widget.verifyPin(pin)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'Incorrect PIN';
        _controller.clear();
      });
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryMuted,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Owner approval required',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                obscureText: _obscure,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Owner PIN',
                  hintText: '4–8 digits',
                  counterText: '',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show PIN' : 'Hide PIN',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeOwnerPinDialog extends StatefulWidget {
  const _ChangeOwnerPinDialog();

  @override
  State<_ChangeOwnerPinDialog> createState() => _ChangeOwnerPinDialogState();
}

class _ChangeOwnerPinDialogState extends State<_ChangeOwnerPinDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length < 4 || pin.length > 8) {
      setState(() => _error = 'PIN must contain 4–8 digits');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set new owner PIN'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _pinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'New PIN',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Confirm PIN',
                counterText: '',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save PIN'),
        ),
      ],
    );
  }
}

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initialValue;
  final String confirmLabel;
  final bool required;
  final int maxLines = 1;
  final Color? confirmColor = null;

  const _TextPromptDialog({
    required this.title,
    required this.label,
    this.initialValue = '',
    this.confirmLabel = 'Save',
  }) : required = true;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.required && value.isEmpty) {
      setState(() => _error = 'This field is required');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: widget.maxLines,
          textInputAction: widget.maxLines == 1
              ? TextInputAction.done
              : TextInputAction.newline,
          onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.confirmColor ?? AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ============================================================================
// SCREEN 7: SALES REPORTING + ORDER HISTORY + OWNER VOID
// ============================================================================
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _filterType = 'Today';
  DateTime _selectedDate = DateTime.now();
  DateTimeRange? _customRange;

  // 1. Add the Scroll Controller
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 2. Listen for scroll events
    _scrollController.addListener(() {
      // If the user scrolls within 200 pixels of the bottom, fetch the next batch
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        Provider.of<PosProvider>(context, listen: false).loadMoreOrders();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  DateTimeRange get _effectiveRange {
    final now = DateTime.now();
    switch (_filterType) {
      case 'Yesterday':
        final y = now.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(y.year, y.month, y.day),
          end: DateTime(y.year, y.month, y.day, 23, 59, 59, 999),
        );
      case 'Specific Date':
        return DateTimeRange(
          start: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
          end: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999),
        );
      case 'This Week':
        final start = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        );
      case 'This Month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        );
      case 'Custom':
        if (_customRange != null) return _customRange!;
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
        );
      case 'Today':
      default:
        return DateTimeRange(
          start: DateTime(now.year, now.month, _selectedDate.day),
          end: DateTime(now.year, now.month, _selectedDate.day, 23, 59, 59, 999),
        );
    }
  }

  bool _matchesRange(CompletedOrder o) {
    final range = _effectiveRange;
    return !o.timestamp.isBefore(range.start) && !o.timestamp.isAfter(range.end);
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _chooseCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customRange ?? DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 7)),
        end: DateTime.now(),
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _customRange = picked);
    }
  }

  Future<void> _voidOrder(BuildContext context, PosProvider pos, CompletedOrder order) async {
    final pinCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Void Bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Owner PIN'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason for Void'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!pos.verifyOwnerPin(pinCtrl.text)) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(
                  const SnackBar(content: Text('Invalid Owner PIN')),
                );
                return;
              }
              Navigator.of(dialogCtx).pop(true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Void Bill'),
          ),
        ],
      ),
    );

    if (verified == true) {
      pos.voidOrder(order.billId, reasonCtrl.text);
    }
  }

  Future<void> _exportToCSV(List<CompletedOrder> ordersToExport) async {
    if (ordersToExport.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data to export.')),
        );
      }
      return;
    }

    try {
      List<List<dynamic>> rows = [];
      rows.add([
        "Bill ID",
        "Date & Time",
        "Total Amount",
        "Payment Method",
        "Status",
        "Items Sold"
      ]);

      for (var order in ordersToExport) {
        String itemsString = order.items.map((i) => '${i.item.name} (x${i.quantity})').join(' | ');
        rows.add([
          order.billId,
          order.timestamp.toString(),
          order.totalAmount,
          order.paymentMethod,
          order.isVoided ? "Voided" : "Completed",
          itemsString,
        ]);
      }

      String csvData = const CsvEncoder().convert(rows);

      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/Friends_Tiffin_Report.csv';

      final File file = File(filePath);
      await file.writeAsString(csvData);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'Friends Tiffin Center - Orders Report',
        ),
      );

    } catch (e) {
      debugPrint('Error exporting CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export report.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final filteredOrders = pos.completedOrders.where(_matchesRange).toList();
    final validOrders = filteredOrders.where((o) => !o.isVoided).toList();
    final voidedOrders = filteredOrders.where((o) => o.isVoided).toList();
    final cashSales = validOrders
        .where((o) => o.paymentMethod == 'CASH')
        .fold<double>(0, (s, o) => s + o.totalAmount);
    final upiSales = validOrders
        .where((o) => o.paymentMethod == 'UPI')
        .fold<double>(0, (s, o) => s + o.totalAmount);
    final totalSales = cashSales + upiSales;
    final dineIn = validOrders.where((o) => o.orderType == 'DINE IN').length;
    final parcel = validOrders.where((o) => o.orderType == 'PARCEL').length;
    final avgBill = validOrders.isEmpty ? 0.0 : totalSales / validOrders.length;
    final range = _effectiveRange;
    final operatingExpenses = pos.operatingExpensesBetween(
      range.start,
      range.end,
    );
    final operatingBalance = totalSales - operatingExpenses;
    final cashExpenseOutflow = pos.cashExpenseOutflowBetween(
      range.start,
      range.end,
    );
    final ownerWithdrawals = pos.ownerCashWithdrawalsBetween(
      range.start,
      range.end,
    );
    final cashAdded = pos.cashAddedBetween(range.start, range.end);

    final rangeLabel = _filterType == 'Specific Date'
        ? DateFormat('dd MMM yyyy').format(_selectedDate)
        : _filterType == 'Custom'
        ? '${DateFormat('dd MMM').format(range.start)} – ${DateFormat('dd MMM yyyy').format(range.end)}'
        : _filterType;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Bill Journal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: () {
              // Pass the list you are currently displaying in the Reports view
              _exportToCSV(filteredOrders);
            },
          ),
        ],
      ),
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children:
                          [
                            'Today',
                            'Yesterday',
                            'Specific Date',
                            'This Week',
                            'This Month',
                            'Custom',
                          ].map((type) {
                            final selected = _filterType == type;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: selected,
                                label: Text(type),
                                selectedColor: AppTheme.primary,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                                onSelected: (_) async {
                                  setState(() => _filterType = type);
                                  if (type == 'Specific Date') {
                                    await _chooseDate();
                                  }
                                  if (type == 'Custom') {
                                    await _chooseCustomRange();
                                  }
                                },
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _filterType == 'Specific Date'
                        ? _chooseDate
                        : _filterType == 'Custom'
                        ? _chooseCustomRange
                        : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rangeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${DateFormat('dd MMM').format(range.start)} – ${DateFormat('dd MMM yyyy').format(range.end)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.elevationLow,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Sales',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '₹${totalSales.toInt()}',
                                  style: const TextStyle(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 22),
                        Wrap(
                          spacing: 20,
                          runSpacing: 14,
                          children: [
                            _metric(
                              'Cash',
                              '₹${cashSales.toInt()}',
                              AppTheme.success,
                            ),
                            _metric(
                              'UPI',
                              '₹${upiSales.toInt()}',
                              const Color(0xFF2563EB),
                            ),
                            _metric(
                              'Bills',
                              '${validOrders.length}',
                              AppTheme.textPrimary,
                            ),
                            _metric(
                              'Avg bill',
                              '₹${avgBill.toInt()}',
                              AppTheme.accent,
                            ),
                            _metric(
                              'Expenses',
                              '₹${operatingExpenses.toInt()}',
                              AppTheme.error,
                            ),
                            _metric(
                              'Op. balance',
                              '₹${operatingBalance.toInt()}',
                              operatingBalance >= 0
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                            _metric(
                              'Cash exp.',
                              '₹${cashExpenseOutflow.toInt()}',
                              AppTheme.accentDark,
                            ),
                            _metric(
                              'Owner out',
                              '₹${ownerWithdrawals.toInt()}',
                              AppTheme.textSecondary,
                            ),
                            _metric(
                              'Cash added',
                              '₹${cashAdded.toInt()}',
                              AppTheme.success,
                            ),
                            _metric('Dine In', '$dineIn', AppTheme.primary),
                            _metric('Parcel', '$parcel', AppTheme.textPrimary),
                            _metric(
                              'Voids',
                              '${voidedOrders.length}',
                              voidedOrders.isEmpty
                                  ? AppTheme.textSecondary
                                  : AppTheme.error,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Bill journal',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        '${filteredOrders.length} records',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredOrders.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 48,
                                  color: AppTheme.textSecondary,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'No sales for this date range.',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                      controller: _scrollController, // <-- Attach controller here
                      itemCount: filteredOrders.length + (pos.isFetchingMoreOrders ? 1 : 0), // Add +1 for the loader
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {

                        // If we reached the end of the list and are fetching more, show the spinner
                        if (index == filteredOrders.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                              final order = filteredOrders[index];
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: order.isVoided
                                        ? AppTheme.error.withValues(alpha: 0.25)
                                        : AppTheme.border,
                                  ),
                                ),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BillReceiptScreen(order: order),
                                      ),
                                    );
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: order.isVoided
                                        ? const Color(0xFFFFEBEE)
                                        : AppTheme.primaryMuted,
                                    child: Icon(
                                      order.isVoided
                                          ? Icons.block_rounded
                                          : Icons.receipt_long_rounded,
                                      color: order.isVoided
                                          ? AppTheme.error
                                          : AppTheme.primary,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Bill #${order.billId} · ${order.orderType}',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            decoration: order.isVoided
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      ),
                                      if (order.isVoided) ...[
                                        const SizedBox(width: 7),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFEBEE),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: const Text(
                                            'VOID',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              color: AppTheme.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    order.isVoided
                                        ? '${DateFormat('dd MMM · hh:mm a').format(order.timestamp)} · ${order.voidReason}'
                                        : '${order.paymentMethod} · ${DateFormat('dd MMM · hh:mm a').format(order.timestamp)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '₹${order.totalAmount.toInt()}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color: order.isVoided
                                              ? AppTheme.textSecondary
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: 'Bill actions',
                                        onSelected: (value) {
                                          if (value == 'view') {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => BillReceiptScreen(order: order),
                                              ),
                                            );
                                          } else if (value == 'void') {
                                            _voidOrder(context, pos, order);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'view',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.receipt_long_rounded,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text('View bill / Print preview'),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'void',
                                            enabled: !order.isVoided,
                                            child: const Row(
                                              children: [
                                                Icon(
                                                  Icons.block_rounded,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Void bill'),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return SizedBox(
      width: 105,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SCREEN 8: EXPENSES & CASH MOVEMENTS
// ============================================================================
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _filter = 'Today';
  DateTime _selectedDate = DateTime.now();

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  DateTimeRange get _range {
    final now = DateTime.now();
    switch (_filter) {
      case 'Yesterday':
        final d = now.subtract(const Duration(days: 1));
        return DateTimeRange(start: _startOfDay(d), end: _endOfDay(d));
      case 'Specific Date':
        return DateTimeRange(
          start: _startOfDay(_selectedDate),
          end: _endOfDay(_selectedDate),
        );
      case 'This Month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: _endOfDay(now),
        );
      case 'All':
        return DateTimeRange(start: DateTime(2020, 1, 1), end: _endOfDay(now));
      default:
        return DateTimeRange(start: _startOfDay(now), end: _endOfDay(now));
    }
  }

  Future<void> _pickSpecificDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _openEditor(PosProvider pos, {ExpenseRecord? existing}) async {
    if (existing != null) {
      final approved = await requestOwnerPin(
        context,
        pos,
        title: 'Edit expense / cash movement',
      );
      if (!approved || !mounted) return;
    }

    final result = await showDialog<ExpenseRecord>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExpenseEntryDialog(pos: pos, existing: existing),
    );
    if (result == null || !mounted) return;

    if (existing == null) {
      pos.addExpense(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.kind == 'EXPENSE'
                ? 'Expense saved.'
                : 'Cash movement saved.',
          ),
        ),
      );
    } else {
      pos.updateExpense(result);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry updated.')));
    }
  }

  Future<void> _deleteEntry(PosProvider pos, ExpenseRecord entry) async {
    final approved = await requestOwnerPin(
      context,
      pos,
      title: 'Delete this entry',
    );
    if (!approved || !mounted) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete entry?'),
            content: Text(
              '${entry.description}\n₹${entry.amount.toStringAsFixed(0)} · ${entry.paymentMethod}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    pos.deleteExpense(entry.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Entry deleted.')));
  }

  void _showReceipt(ExpenseRecord entry) {
    if (entry.receiptDataUrl.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Receipt / Bill',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: AppMenuImage(
                    source: entry.receiptDataUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final range = _range;
    final entries = pos.expensesBetween(range.start, range.end)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final businessExpenses = entries
        .where((e) => e.kind == 'EXPENSE')
        .fold<double>(0, (s, e) => s + e.amount);
    final cashExpenses = entries
        .where((e) => e.kind == 'EXPENSE' && e.paymentMethod == 'CASH')
        .fold<double>(0, (s, e) => s + e.amount);
    final digitalExpenses = entries
        .where((e) => e.kind == 'EXPENSE' && e.paymentMethod != 'CASH')
        .fold<double>(0, (s, e) => s + e.amount);
    final withdrawals = entries
        .where((e) => e.kind == 'OWNER WITHDRAWAL')
        .fold<double>(0, (s, e) => s + e.amount);
    final cashAdded = entries
        .where((e) => e.kind == 'CASH ADDED')
        .fold<double>(0, (s, e) => s + e.amount);

    final sales = pos.completedOrders
        .where(
          (o) =>
              !o.isVoided &&
              !o.timestamp.isBefore(range.start) &&
              !o.timestamp.isAfter(range.end),
        )
        .fold<double>(0, (s, o) => s + o.totalAmount);
    final operatingBalance = sales - businessExpenses;

    final rangeLabel = _filter == 'Specific Date'
        ? DateFormat('dd MMM yyyy').format(_selectedDate)
        : _filter == 'All'
        ? 'All recorded entries'
        : _filter;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Expenses · செலவு'),
        actions: [
          IconButton(
            tooltip: 'Add expense',
            onPressed: () => _openEditor(pos),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(pos),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'ADD EXPENSE',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children:
                          [
                            'Today',
                            'Yesterday',
                            'Specific Date',
                            'This Month',
                            'All',
                          ].map((type) {
                            final selected = _filter == type;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: selected,
                                label: Text(type),
                                selectedColor: AppTheme.primary,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                                onSelected: (_) async {
                                  setState(() => _filter = type);
                                  if (type == 'Specific Date') {
                                    await _pickSpecificDate();
                                  }
                                },
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _filter == 'Specific Date'
                        ? _pickSpecificDate
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              rangeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (_filter != 'All') ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${DateFormat('dd MMM').format(range.start)} – ${DateFormat('dd MMM yyyy').format(range.end)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 720;
                      final cards = [
                        _expenseMetric(
                          'Sales',
                          sales,
                          Icons.point_of_sale_rounded,
                          AppTheme.primary,
                        ),
                        _expenseMetric(
                          'Business expenses',
                          businessExpenses,
                          Icons.shopping_bag_outlined,
                          AppTheme.error,
                        ),
                        _expenseMetric(
                          'Operating balance',
                          operatingBalance,
                          Icons.account_balance_wallet_outlined,
                          operatingBalance >= 0
                              ? AppTheme.success
                              : AppTheme.error,
                        ),
                        _expenseMetric(
                          'Cash expenses',
                          cashExpenses,
                          Icons.payments_outlined,
                          AppTheme.accentDark,
                        ),
                      ];
                      if (compact) {
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: cards
                              .map(
                                (w) => SizedBox(
                                  width: (constraints.maxWidth - 8) / 2,
                                  child: w,
                                ),
                              )
                              .toList(),
                        );
                      }
                      return Row(
                        children: cards
                            .map(
                              (w) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: w,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        _miniSummary('UPI/Bank expenses', digitalExpenses),
                        _miniSummary('Owner withdrawals', withdrawals),
                        _miniSummary('Cash added', cashAdded, positive: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Expense journal',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${entries.length} entries',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryMuted,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long_outlined,
                                    color: AppTheme.primary,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No expenses recorded for this period.',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap “Add Expense” to record a purchase or cash movement.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 86),
                            itemCount: entries.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              final isAdded = entry.kind == 'CASH ADDED';
                              final isWithdrawal =
                                  entry.kind == 'OWNER WITHDRAWAL';
                              final color = isAdded
                                  ? AppTheme.success
                                  : (isWithdrawal
                                        ? AppTheme.accentDark
                                        : AppTheme.error);
                              final icon = isAdded
                                  ? Icons.add_card_rounded
                                  : isWithdrawal
                                  ? Icons.person_remove_alt_1_outlined
                                  : Icons.shopping_cart_checkout_rounded;
                              final kindLabel = isAdded
                                  ? 'CASH ADDED'
                                  : (isWithdrawal
                                        ? 'OWNER WITHDRAWAL'
                                        : entry.category.toUpperCase());

                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    12,
                                    6,
                                    4,
                                    6,
                                  ),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(icon, color: color, size: 21),
                                  ),
                                  title: Text(
                                    entry.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 2),
                                      Text(
                                        '$kindLabel · ${entry.paymentMethod} · ${DateFormat('dd MMM, hh:mm a').format(entry.timestamp)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (entry.supplier.trim().isNotEmpty)
                                        Text(
                                          entry.supplier,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 90,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            '${isAdded ? '+' : '-'}₹${entry.amount.toInt()}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: 'Entry actions',
                                        onSelected: (value) {
                                          if (value == 'receipt') {
                                            _showReceipt(entry);
                                          }
                                          if (value == 'edit') {
                                            _openEditor(pos, existing: entry);
                                          }
                                          if (value == 'delete') {
                                            _deleteEntry(pos, entry);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          if (entry.receiptDataUrl.isNotEmpty)
                                            const PopupMenuItem(
                                              value: 'receipt',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.image_outlined,
                                                    size: 18,
                                                    color: AppTheme.info,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('View receipt'),
                                                ],
                                              ),
                                            ),
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Edit'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 18,
                                                  color: AppTheme.error,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Delete'),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _expenseMetric(
    String label,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.elevationLow,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '₹${amount.toInt()}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniSummary(String label, double amount, {bool positive = false}) {
    return Text(
      '$label: ${positive ? '+' : ''}₹${amount.toInt()}',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: positive ? AppTheme.success : AppTheme.primary,
      ),
    );
  }
}

class _ExpenseEntryDialog extends StatefulWidget {
  final PosProvider pos;
  final ExpenseRecord? existing;

  const _ExpenseEntryDialog({required this.pos, this.existing});

  @override
  State<_ExpenseEntryDialog> createState() => _ExpenseEntryDialogState();
}

class _ExpenseEntryDialogState extends State<_ExpenseEntryDialog> {
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _supplierCtrl;
  late final TextEditingController _notesCtrl;
  late String _kind;
  late String _category;
  late String _paymentMethod;
  late DateTime _date;
  late String _receiptDataUrl;
  String? _error;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _descriptionCtrl = TextEditingController(text: e?.description ?? '');
    _amountCtrl = TextEditingController(
      text: e == null
          ? ''
          : e.amount.toStringAsFixed(e.amount % 1 == 0 ? 0 : 2),
    );
    _supplierCtrl = TextEditingController(text: e?.supplier ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _kind = e?.kind ?? 'EXPENSE';
    _category = e?.category ?? widget.pos.expenseCategories.first;
    if (!widget.pos.expenseCategories.contains(_category)) {
      widget.pos.expenseCategories.add(_category);
    }
    _paymentMethod = e?.paymentMethod ?? 'CASH';
    _date = e?.timestamp ?? DateTime.now();
    _receiptDataUrl = e?.receiptDataUrl ?? '';
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _amountCtrl.dispose();
    _supplierCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
        _date.second,
      );
    });
  }

  Future<void> _pickReceipt() async {
    setState(() {
      _pickingImage = true;
      _error = null;
    });
    try {
      final data = await pickLocalImageDataUrl(maxBytes: 800000);
      if (!mounted || data == null) return;
      setState(() => _receiptDataUrl = data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _addCategory() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPromptDialog(
        title: 'New expense category',
        label: 'Example: Bakery / Maintenance',
        confirmLabel: 'Add category',
      ),
    );
    if (value == null || !mounted) return;
    final clean = value.trim();
    if (clean.isEmpty) return;
    final added = widget.pos.addExpenseCategory(clean);
    if (!added) {
      setState(() => _error = 'That category already exists.');
      return;
    }
    setState(() => _category = clean);
  }

  void _save() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final description = _descriptionCtrl.text.trim();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than zero.');
      return;
    }
    if (description.isEmpty) {
      setState(() => _error = 'Enter a short description.');
      return;
    }

    final original = widget.existing;
    final timestamp = original == null
        ? DateTime(
            _date.year,
            _date.month,
            _date.day,
            DateTime.now().hour,
            DateTime.now().minute,
            DateTime.now().second,
          )
        : _date;
    Navigator.pop(
      context,
      ExpenseRecord(
        id: original?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: timestamp,
        kind: _kind,
        category: _kind == 'EXPENSE'
            ? _category
            : (_kind == 'CASH ADDED' ? 'Cash Added' : 'Owner Withdrawal'),
        description: description,
        amount: amount,
        paymentMethod: _kind == 'CASH ADDED' ? 'CASH' : _paymentMethod,
        supplier: _kind == 'EXPENSE' ? _supplierCtrl.text.trim() : '',
        notes: _notesCtrl.text.trim(),
        receiptDataUrl: _receiptDataUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Add Expense / Cash Movement'
                          : 'Edit Entry',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'TYPE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _kindChip(
                          'EXPENSE',
                          'Business Expense',
                          Icons.shopping_bag_outlined,
                        ),
                        _kindChip(
                          'OWNER WITHDRAWAL',
                          'Owner Withdrawal',
                          Icons.person_remove_alt_1_outlined,
                        ),
                        _kindChip(
                          'CASH ADDED',
                          'Cash Added',
                          Icons.add_card_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount',
                              prefixText: '₹ ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _chooseDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date',
                                suffixIcon: Icon(Icons.calendar_month_rounded),
                              ),
                              child: Text(
                                DateFormat('dd MMM yyyy').format(_date),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descriptionCtrl,
                      decoration: InputDecoration(
                        labelText: _kind == 'EXPENSE'
                            ? 'Description'
                            : (_kind == 'CASH ADDED'
                                  ? 'Source / reason'
                                  : 'Reason for withdrawal'),
                        hintText: _kind == 'EXPENSE'
                            ? 'Example: Morning vegetable purchase'
                            : null,
                      ),
                    ),
                    if (_kind == 'EXPENSE') ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  widget.pos.expenseCategories.contains(
                                    _category,
                                  )
                                  ? _category
                                  : widget.pos.expenseCategories.first,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                              ),
                              items: widget.pos.expenseCategories
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c,
                                      child: Text(
                                        c,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _category = v);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Add category',
                            onPressed: _addCategory,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _supplierCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Supplier / person (optional)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'PAYMENT MODE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      children: ['CASH', 'UPI', 'BANK'].map((method) {
                        final disabled =
                            _kind == 'CASH ADDED' && method != 'CASH';
                        final selected =
                            (_kind == 'CASH ADDED' ? 'CASH' : _paymentMethod) ==
                            method;
                        return ChoiceChip(
                          selected: selected,
                          label: Text(method),
                          onSelected: disabled
                              ? null
                              : (_) => setState(() => _paymentMethod = method),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              if (_receiptDataUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: AppMenuImage(
                                    source: _receiptDataUrl,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long_outlined,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Receipt photo',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Optional · stored locally · max 800 KB',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (_receiptDataUrl.isNotEmpty)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        setState(() => _receiptDataUrl = ''),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: AppTheme.error,
                                    ),
                                    label: const Text('Remove'),
                                  ),
                                ),
                              if (_receiptDataUrl.isNotEmpty)
                                const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _pickingImage
                                      ? null
                                      : _pickReceipt,
                                  icon: _pickingImage
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.photo_library_outlined,
                                          size: 18,
                                        ),
                                  label: Text(
                                    _receiptDataUrl.isEmpty
                                        ? 'Choose photo'
                                        : 'Change photo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('SAVE ENTRY'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindChip(String value, String label, IconData icon) {
    final selected = _kind == value;
    return ChoiceChip(
      selected: selected,
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : AppTheme.textSecondary,
      ),
      label: Text(label),
      selectedColor: AppTheme.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      onSelected: (_) {
        setState(() {
          _kind = value;
          if (value == 'CASH ADDED') _paymentMethod = 'CASH';
          _error = null;
        });
      },
    );
  }
}

// ============================================================================
// SCREEN 8: CLOSING CASH DRAWER RECONCILIATION (கல்லா கணக்கு)
// ============================================================================
class DenominationScreen extends StatefulWidget {
  const DenominationScreen({super.key});
  @override
  State<DenominationScreen> createState() => _DenominationScreenState();
}

class _DenominationScreenState extends State<DenominationScreen> {
  final List<int> notes = [500, 200, 100, 50, 20, 10, 5, 2, 1];
  late final Map<int, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final note in notes) note: TextEditingController(text: '0'),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int _getCount(int note) =>
      int.tryParse(_controllers[note]?.text.trim() ?? '') ?? 0;

  int get totalCounted =>
      notes.fold<int>(0, (acc, note) => acc + note * _getCount(note));

  void _updateCount(int note, int delta) {
    final updated = (_getCount(note) + delta).clamp(0, 99999);
    setState(() {
      _controllers[note]?.text = updated.toString();
      _controllers[note]?.selection = TextSelection.fromPosition(
        TextPosition(offset: _controllers[note]!.text.length),
      );
    });
  }

  void _clearAll() {
    setState(() {
      for (final note in notes) {
        _controllers[note]?.text = '0';
      }
    });
  }

  Future<void> _saveClosing(
    BuildContext context,
    PosProvider pos, {
    required double expectedCash,
    required double upiSales,
    required double totalSales,
    required int orderCount,
    required double cashExpenses,
    required double ownerWithdrawals,
    required double cashAdded,
    required double operatingExpenses,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final approved = await requestOwnerPin(
      context,
      pos,
      title: 'Save day closing',
    );
    if (!approved || !mounted) return;

    pos.saveDayClose(
      expectedCash: expectedCash,
      countedCash: totalCounted.toDouble(),
      upiSales: upiSales,
      totalSales: totalSales,
      orderCount: orderCount,
      cashExpenses: cashExpenses,
      ownerWithdrawals: ownerWithdrawals,
      cashAdded: cashAdded,
      operatingExpenses: operatingExpenses,
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Day closing saved. The cash variance is now recorded.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final now = DateTime.now();
    final todayOrders = pos.completedOrders
        .where(
          (o) =>
              !o.isVoided &&
              o.timestamp.year == now.year &&
              o.timestamp.month == now.month &&
              o.timestamp.day == now.day,
        )
        .toList();

    final todayCashSales = todayOrders
        .where((o) => o.paymentMethod == 'CASH')
        .fold<double>(0, (acc, o) => acc + o.totalAmount);
    final todayUpiSales = todayOrders
        .where((o) => o.paymentMethod == 'UPI')
        .fold<double>(0, (acc, o) => acc + o.totalAmount);
    final totalSales = todayCashSales + todayUpiSales;
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final cashExpenses = pos.cashExpenseOutflowBetween(dayStart, dayEnd);
    final ownerWithdrawals = pos.ownerCashWithdrawalsBetween(dayStart, dayEnd);
    final cashAdded = pos.cashAddedBetween(dayStart, dayEnd);
    final operatingExpenses = pos.operatingExpensesBetween(dayStart, dayEnd);
    final expectedCash =
        todayCashSales - cashExpenses - ownerWithdrawals + cashAdded;
    final difference = totalCounted - expectedCash;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('கல்லா கணக்கு · Day Close'),
        actions: [
          IconButton(
            tooltip: 'Clear counts',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
                boxShadow: AppTheme.elevationLow,
              ),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      Widget metric(String label, String value, Color color) =>
                          Expanded(child: _closeMetric(label, value, color));
                      if (constraints.maxWidth < 520) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                metric(
                                  'Cash sales',
                                  '₹${todayCashSales.toInt()}',
                                  AppTheme.success,
                                ),
                                const SizedBox(width: 12),
                                metric(
                                  'UPI',
                                  '₹${todayUpiSales.toInt()}',
                                  const Color(0xFF2563EB),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                metric(
                                  'Total',
                                  '₹${totalSales.toInt()}',
                                  AppTheme.primary,
                                ),
                                const SizedBox(width: 12),
                                metric(
                                  'Bills',
                                  '${todayOrders.length}',
                                  AppTheme.textPrimary,
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          metric(
                            'Cash sales',
                            '₹${todayCashSales.toInt()}',
                            AppTheme.success,
                          ),
                          metric(
                            'UPI',
                            '₹${todayUpiSales.toInt()}',
                            const Color(0xFF2563EB),
                          ),
                          metric(
                            'Total',
                            '₹${totalSales.toInt()}',
                            AppTheme.primary,
                          ),
                          metric(
                            'Bills',
                            '${todayOrders.length}',
                            AppTheme.textPrimary,
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Cash expenses −₹${cashExpenses.toInt()}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.error,
                        ),
                      ),
                      Text(
                        'Owner withdrawals −₹${ownerWithdrawals.toInt()}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentDark,
                        ),
                      ),
                      Text(
                        'Cash added +₹${cashAdded.toInt()}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Counted cash',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '₹$totalCounted',
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Expected cash',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '₹${expectedCash.toInt()}',
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Variance',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                difference >= 0
                                    ? '+₹${difference.toInt()}'
                                    : '-₹${(-difference).toInt()}',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                  color: difference == 0
                                      ? AppTheme.success
                                      : (difference > 0
                                            ? const Color(0xFF2563EB)
                                            : AppTheme.error),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (pos.dayCloses.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Last close ${DateFormat('dd MMM, hh:mm a').format(pos.dayCloses.first.timestamp)} · Counted ₹${pos.dayCloses.first.countedCash.toInt()} · Variance ${pos.dayCloses.first.variance >= 0 ? '+' : '-'}₹${pos.dayCloses.first.variance.abs().toInt()}",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  final controller = _controllers[note]!;
                  final count = _getCount(note);
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            '₹$note',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        const Text(
                          '×',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: AppTheme.error,
                          ),
                          onPressed: () => _updateCount(note, -1),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 64,
                          height: 38,
                          child: TextField(
                            controller: controller,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: AppTheme.primary,
                          ),
                          onPressed: () => _updateCount(note, 1),
                        ),
                        const Spacer(),
                        Text(
                          '₹${note * count}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveClosing(
                      context,
                      pos,
                      expectedCash: expectedCash,
                      upiSales: todayUpiSales,
                      totalSales: totalSales,
                      orderCount: todayOrders.length,
                      cashExpenses: cashExpenses,
                      ownerWithdrawals: ownerWithdrawals,
                      cashAdded: cashAdded,
                      operatingExpenses: operatingExpenses,
                    ),
                    icon: const Icon(Icons.lock_clock_rounded),
                    label: Text(
                      'SAVE DAY CLOSE · ${DateFormat('dd MMM').format(now)}',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closeMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// APP VERSION & MANUAL UPDATE CHECK SYSTEM
// ============================================================================
const String kCurrentAppVersion = '1.0.8';
const int kCurrentAppVersionCode = 8;

class AppUpdateInfo {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;

  AppUpdateInfo({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.releaseNotes,
    this.forceUpdate = false,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        version: json['version']?.toString() ?? '1.0.0',
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 1,
        downloadUrl: json['downloadUrl']?.toString() ?? '',
        releaseNotes: json['releaseNotes']?.toString() ??
            'General bug fixes, speed optimizations and stability improvements.',
        forceUpdate: json['forceUpdate'] as bool? ?? false,
      );
}

Future<void> checkAppUpdate(BuildContext context, {bool showNoUpdateDialog = true}) async {
  ScaffoldMessengerState? messenger;
  if (showNoUpdateDialog && context.mounted) {
    messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Checking for app updates...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );
  }

  try {
    final docSnap = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('latest_version')
        .get();

    if (messenger != null) {
      messenger.hideCurrentSnackBar();
    }

    if (!docSnap.exists || docSnap.data() == null) {
      if (showNoUpdateDialog && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your app is up to date! (v$kCurrentAppVersion)'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
      return;
    }

    final updateInfo = AppUpdateInfo.fromJson(docSnap.data()!);

    final isNewerVersionCode = updateInfo.versionCode > kCurrentAppVersionCode;
    final isNewerVersionName = updateInfo.version.trim() != kCurrentAppVersion &&
        updateInfo.version.trim().isNotEmpty;

    if (isNewerVersionCode || isNewerVersionName) {
      if (context.mounted) {
        showAppUpdateDialog(context, updateInfo);
      }
    } else {
      if (showNoUpdateDialog && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are using the latest version (v$kCurrentAppVersion).'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('Error checking app update: $e');
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
    }
    if (showNoUpdateDialog && context.mounted) {
      final errorStr = e.toString();
      final message = (errorStr.contains('unavailable') || errorStr.contains('network') || errorStr.contains('SocketException') || errorStr.contains('not-found'))
          ? 'You are using the latest version (v$kCurrentAppVersion). (Offline)'
          : 'Failed to check for updates. Please try again later.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }
}

void showAppUpdateDialog(BuildContext context, AppUpdateInfo updateInfo) {
  showDialog(
    context: context,
    barrierDismissible: !updateInfo.forceUpdate,
    builder: (dialogCtx) => PopScope(
      canPop: !updateInfo.forceUpdate,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'New Update Available',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v${updateInfo.version}  (Installed: v$kCurrentAppVersion)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'What\'s New:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                updateInfo.releaseNotes,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
           if (!updateInfo.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Later', style: TextStyle(color: AppTheme.textSecondary)),
            ),
          ElevatedButton.icon(
            onPressed: () async {
              if (updateInfo.downloadUrl.isNotEmpty) {
                try {
                  final uri = Uri.parse(updateInfo.downloadUrl);
                  
                  // Use LaunchMode.externalNonBrowserApplication which forces standard app handling for APK links,
                  // falling back to LaunchMode.externalApplication if needed
                  final launched = await launchUrl(
                    uri, 
                    mode: LaunchMode.externalNonBrowserApplication,
                  ).catchError((_) async {
                    return await launchUrl(uri, mode: LaunchMode.externalApplication);
                  });
                  
                  if (!launched && dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      const SnackBar(content: Text('Could not open download link.')),
                    );
                  }
                } catch (e) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(content: Text('Could not open download link: $e')),
                    );
                  }
                }
              }
            },
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text('DOWNLOAD & INSTALL'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

// ============================================================================
// STAFF MANAGEMENT SCREEN (For Owners)
// ============================================================================
class StaffManagementScreen extends StatelessWidget {
  const StaffManagementScreen({super.key});

  void _showStaffDetailDialog(
    BuildContext context,
    String ownerEmail,
    String staffId,
    Map<String, dynamic> data,
  ) {
    final name = data['name'] ?? 'Unknown';
    final mobile = data['mobile'] ?? 'No Mobile';
    final status = data['status'] ?? 'pending';
    final createdAt = data['createdAt'] ?? '';
    bool isActive = status == 'active';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isActive ? AppTheme.primaryMuted : Colors.orange.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.person,
                      color: isActive ? AppTheme.primary : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Staff ID: $staffId',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  _detailRow(Icons.phone_android_rounded, 'Mobile Number', mobile),
                  const SizedBox(height: 12),
                  _detailRow(
                    isActive ? Icons.check_circle_rounded : Icons.pending_rounded,
                    'Account Status',
                    isActive ? 'Active (Verified)' : 'Pending Verification',
                    color: isActive ? AppTheme.success : Colors.orange,
                  ),
                  if (createdAt.toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _detailRow(Icons.calendar_today_rounded, 'Requested On', _formatDate(createdAt.toString())),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Allow System Access',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        Switch(
                          value: isActive,
                          activeThumbColor: AppTheme.primary,
                          onChanged: (val) async {
                            final newStatus = val ? 'active' : 'pending';
                            final updateData = {
                              'status': newStatus,
                              'updatedAt': DateTime.now().toIso8601String(),
                            };
                            try {
                              await FirebaseFirestore.instance
                                  .collection('staff_requests')
                                  .doc(staffId)
                                  .update(updateData);
                            } catch (_) {}
                            try {
                              await FirebaseFirestore.instance
                                  .collection('pos_users')
                                  .doc(ownerEmail)
                                  .collection('staff')
                                  .doc(staffId)
                                  .update(updateData);
                            } catch (_) {}
                            try {
                              await FirebaseFirestore.instance
                                  .collection('restaurants')
                                  .doc(ownerEmail)
                                  .collection('staff')
                                  .doc(staffId)
                                  .update(updateData);
                            } catch (_) {}
                            setDialogState(() {
                              isActive = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 18),
                  label: const Text('Delete Staff', style: TextStyle(color: AppTheme.error)),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Staff Account?'),
                        content: Text('Are you sure you want to remove $name (ID: $staffId)?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && context.mounted) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('staff_requests')
                            .doc(staffId)
                            .delete();

                        await FirebaseFirestore.instance
                            .collection('pos_users')
                            .doc(ownerEmail)
                            .collection('staff')
                            .doc(staffId)
                            .delete();

                        await FirebaseFirestore.instance
                            .collection('restaurants')
                            .doc(ownerEmail)
                            .collection('staff')
                            .doc(staffId)
                            .delete();

                        await FirebaseFirestore.instance
                            .collection('staff_accounts')
                            .doc(staffId)
                            .delete();
                      } catch (_) {}

                      if (!dialogCtx.mounted) return;
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Staff member $name deleted.')),
                      );
                    }
                  },
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? AppTheme.textSecondary),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color ?? AppTheme.textPrimary),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final authEmail = (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();
    final isStaffAuth = authEmail.endsWith('@staff.pos');
    
    final ownerEmail = (isStaffAuth ? pos.currentUserEmail : authEmail).trim().toLowerCase();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Manage Staff')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('staff_requests')
            .where('storeEmail', isEqualTo: ownerEmail)
            .snapshots(),
        builder: (context, snapRequests) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('pos_users')
                .doc(ownerEmail)
                .collection('staff')
                .snapshots(),
            builder: (context, snapPosUsers) {
              if (snapRequests.connectionState == ConnectionState.waiting &&
                  snapPosUsers.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final Map<String, Map<String, dynamic>> staffMap = {};

              if (snapRequests.hasData) {
                for (final doc in snapRequests.data!.docs) {
                  staffMap[doc.id] = doc.data() as Map<String, dynamic>;
                }
              }

              if (snapPosUsers.hasData) {
                for (final doc in snapPosUsers.data!.docs) {
                  staffMap[doc.id] = doc.data() as Map<String, dynamic>;
                }
              }

              if (staffMap.isEmpty) {
                return const Center(
                  child: Text(
                    'No staff members found.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                );
              }

              final staffItems = staffMap.entries.toList();
              staffItems.sort((a, b) {
                final aCreated = a.value['createdAt']?.toString() ?? '';
                final bCreated = b.value['createdAt']?.toString() ?? '';
                if (aCreated.isNotEmpty && bCreated.isNotEmpty) {
                  return bCreated.compareTo(aCreated);
                }
                return b.key.compareTo(a.key);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: staffItems.length,
                itemBuilder: (context, index) {
                  final staffId = staffItems[index].key;
                  final data = staffItems[index].value;
                  final name = data['name'] ?? 'Unknown';
                  final mobile = data['mobile'] ?? 'No Mobile';
                  final status = data['status'] ?? 'pending';
                  final isActive = status == 'active';

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppTheme.border),
                    ),
                    child: ListTile(
                      onTap: () => _showStaffDetailDialog(context, ownerEmail, staffId, data),
                      leading: CircleAvatar(
                        backgroundColor: isActive ? AppTheme.primaryMuted : Colors.orange.withValues(alpha: 0.2),
                        child: Icon(
                          Icons.person,
                          color: isActive ? AppTheme.primary : Colors.orange,
                        ),
                      ),
                      title: Text('$name (ID: $staffId)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Mobile: $mobile\nStatus: ${status.toUpperCase()}'),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: isActive,
                            activeThumbColor: AppTheme.primary,
                            onChanged: (bool value) async {
                              final newStatus = value ? 'active' : 'pending';
                              final updateData = {
                                'status': newStatus,
                                'updatedAt': DateTime.now().toIso8601String(),
                              };
                              try {
                                await FirebaseFirestore.instance
                                    .collection('staff_requests')
                                    .doc(staffId)
                                    .update(updateData);
                              } catch (_) {}
                              try {
                                await FirebaseFirestore.instance
                                    .collection('pos_users')
                                    .doc(ownerEmail)
                                    .collection('staff')
                                    .doc(staffId)
                                    .update(updateData);
                              } catch (_) {}
                              try {
                                await FirebaseFirestore.instance
                                    .collection('restaurants')
                                    .doc(ownerEmail)
                                    .collection('staff')
                                    .doc(staffId)
                                    .update(updateData);
                              } catch (_) {}
                                  
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Staff ID $staffId is now $newStatus.')),
                              );
                            },
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// SCREEN 9: SETTINGS & BACK-OFFICE HUB
// ============================================================================
class MainSettingsScreen extends StatelessWidget {
  const MainSettingsScreen({super.key});

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.elevationLow,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryMuted,
          child: Icon(icon, color: iconColor ?? AppTheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Colors.grey,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _featureToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? AppTheme.primary.withValues(alpha: 0.28)
              : AppTheme.border,
        ),
        boxShadow: AppTheme.elevationLow,
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: CircleAvatar(
          backgroundColor: value ? AppTheme.primaryMuted : AppTheme.surface,
          child: Icon(
            icon,
            color: value ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        activeThumbColor: AppTheme.primary,
      ),
    );
  }

  Future<void> _openProtected(
    BuildContext context,
    PosProvider pos,
    Widget page,
    String title,
  ) async {
    final approved = await requestOwnerPin(context, pos, title: title);
    if (!approved || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _changeOwnerPin(BuildContext context, PosProvider pos) async {
    final approved = await requestOwnerPin(
      context,
      pos,
      title: 'Change owner PIN',
    );
    if (!approved || !context.mounted) return;

    final newPin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangeOwnerPinDialog(),
    );
    if (newPin == null || !context.mounted) return;

    pos.changeOwnerPin(newPin);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Owner PIN updated successfully.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Settings & Configuration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Devices & alerts',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _featureToggle(
            icon: Icons.volume_up_rounded,
            title: 'Sound Box',
            subtitle: pos.isSoundboxEnabled
                ? 'Payment voice announcements are ON'
                : 'Off by default · no voice announcements',
            value: pos.isSoundboxEnabled,
            onChanged: (value) => pos.setSoundboxEnabled(value),
          ),
          const SizedBox(height: 10),
          _featureToggle(
            icon: Icons.print_rounded,
            title: 'Thermal Printer',
            subtitle: pos.isPrinterEnabled
                ? 'Printer features are enabled'
                : 'Off by default · no Bluetooth printing attempts',
            value: pos.isPrinterEnabled,
            onChanged: pos.setPrinterEnabled,
          ),
          if (!pos.isStaffUser) ...[
            const SizedBox(height: 18),
            const Text(
              'Owner controls',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            _settingsTile(
              icon: Icons.people_alt_outlined,
              title: 'Manage Staff',
              subtitle: 'Verify and activate pending staff accounts',
              onTap: () => _openProtected(
                context,
                pos,
                const StaffManagementScreen(),
                'Manage Staff',
              ),
            ),
            const SizedBox(height: 10),
            _settingsTile(
              icon: Icons.lock_person_outlined,
              title: 'Owner PIN',
              subtitle:
                  'Protects menu changes, voids and day closing · default PIN is 1234',
              onTap: () => _changeOwnerPin(context, pos),
            ),
            const SizedBox(height: 10),
            _settingsTile(
              icon: Icons.receipt_long_rounded,
              title: 'Expenses & Cash Movements',
              subtitle:
                  'Business costs, owner withdrawals, cash added and receipt photos',
              onTap: () => _openProtected(
                context,
                pos,
                const ExpensesScreen(),
                'Expenses & Cash Movements',
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Configuration',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.textSecondary,
            ),
          ),
          if (!pos.isStaffUser) ...[
            const SizedBox(height: 10),
            _settingsTile(
              icon: Icons.restaurant_menu,
              title: 'Menu Catalog (பட்டியல்)',
              subtitle: 'Add items, prices, pictures and Sold Out status',
              onTap: () => _openProtected(
                context,
                pos,
                const MenuManagementScreen(),
                'Open menu management',
              ),
            ),
            const SizedBox(height: 10),
            _settingsTile(
              icon: Icons.category_outlined,
              title: 'Categories (வகைகள்)',
              subtitle: 'Manage category tabs and menu organization',
              onTap: () => _openProtected(
                context,
                pos,
                const CategoryManagementScreen(),
                'Open category management',
              ),
            ),
            const SizedBox(height: 10),
            _settingsTile(
              icon: Icons.receipt_long,
              title: 'Store & Soundbox Template',
              subtitle: 'Brand name, UPI address and receipt details',
              onTap: () => _openProtected(
                context,
                pos,
                const TemplateSettingsScreen(),
                'Open store configuration',
              ),
            ),
          ],
          const SizedBox(height: 10),
          _settingsTile(
            icon: Icons.print_outlined,
            title: 'Bluetooth POS Printer',
            subtitle: 'Pair 58mm/80mm wireless thermal bill printers',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrinterSetupScreen()),
            ),
          ),
          if (!pos.isStaffUser) ...[
            const SizedBox(height: 18),
            const Text(
              'Multi-Device Sync Role',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            _featureToggle(
              icon: pos.isOwnerDevice ? Icons.admin_panel_settings_rounded : Icons.point_of_sale_rounded,
              title: pos.isOwnerDevice ? 'Owner Device (All Bills Synced)' : 'Staff Device (Today\'s Bills Synced)',
              subtitle: pos.isOwnerDevice
                  ? 'Owner Mode · Synchronizes all historical bills, revenue journal and reports'
                  : 'Staff/Counter Mode · Syncs active counter bills and today\'s orders',
              value: pos.isOwnerDevice,
              onChanged: (value) async {
                if (value) {
                  final approved = await requestOwnerPin(context, pos, title: 'Switch to Owner Device Mode');
                  if (!approved || !context.mounted) return;
                }
                await pos.setOwnerDeviceMode(value);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        value
                            ? 'Switched to Owner Device (All bills & full history synced).'
                            : 'Switched to Staff Device (Syncing counter & today\'s bills).',
                      ),
                    ),
                  );
                }
              },
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            'App Information & Updates',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _featureToggle(
            icon: Icons.system_update_rounded,
            title: 'Automatic Update Check',
            subtitle: pos.isAutoUpdateCheckEnabled
                ? 'Checks for app updates automatically on startup'
                : 'Off · manual checks only via button',
            value: pos.isAutoUpdateCheckEnabled,
            onChanged: (value) => pos.setAutoUpdateCheckEnabled(value),
          ),
          const SizedBox(height: 10),
          _settingsTile(
            icon: Icons.system_update_rounded,
            iconColor: AppTheme.primary,
            title: 'Check for App Updates',
            subtitle: 'Installed Version: v$kCurrentAppVersion · Tap to check online',
            onTap: () => checkAppUpdate(context, showNoUpdateDialog: true),
          ),
          const SizedBox(height: 24),
          const Text(
            'Account',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppTheme.error,
            ),
          ),
          const SizedBox(height: 10),
          _settingsTile(
            icon: Icons.logout_rounded,
            iconColor: AppTheme.error,
            title: 'Logout',
            subtitle: 'Sign out and return to the login screen',
            onTap: () async {
              final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Logout?'),
                    content: const Text('Are you sure you want to sign out? Your data is synced securely to the cloud.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Logout')
                      ),
                    ],
                  )
              );

              if (confirm != true || !context.mounted) return;

              // 1. Clear provider state immediately for UI snap
              await Provider.of<PosProvider>(context, listen: false).logout();

              // 2. Tell Firebase to terminate the session.
              // The stream in AuthGate will detect this and automatically pop back to LoginScreen.
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SCREEN 10: CATEGORY MANAGEMENT
// ============================================================================
class CategoryManagementScreen extends StatelessWidget {
  const CategoryManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Manage Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openCategoryDialog(context, null),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: pos.categories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final cat = pos.categories[i];
          final isDefault = cat == 'All';

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: ListTile(
              title: Text(
                cat,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: isDefault
                  ? const Chip(label: Text('System'))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: AppTheme.primary),
                          onPressed: () => _openCategoryDialog(context, cat),
                        ),
                        IconButton(
                          tooltip: 'Delete category',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppTheme.error,
                          ),
                          onPressed: () {
                            final deleted = pos.deleteCategory(cat);
                            if (!deleted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Cannot delete “$cat” while menu items still use it. Move those dishes first.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCategoryDialog(BuildContext context, String? oldCat) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: oldCat == null ? 'Add Category' : 'Rename Category',
        label: 'Category title',
        initialValue: oldCat ?? '',
      ),
    );
    if (value == null || value.trim().isEmpty || !context.mounted) return;

    final pos = Provider.of<PosProvider>(context, listen: false);
    final saved = oldCat == null
        ? pos.addCategory(value.trim())
        : pos.editCategory(oldCat, value.trim());
    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category name is empty, reserved, or already exists.'),
        ),
      );
    }
  }
} // ============================================================================

// SCREEN 11: MENU MANAGEMENT — safe, responsive CRUD
// ============================================================================
class MenuManagementScreen extends StatelessWidget {
  const MenuManagementScreen({super.key});

  Future<void> _openItemDialog(
    BuildContext context,
    MenuItem? existingItem,
  ) async {
    final pos = Provider.of<PosProvider>(context, listen: false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _MenuItemEditorDialog(pos: pos, existingItem: existingItem),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PosProvider pos,
    MenuItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete menu item?'),
        content: Text(
          '${item.name} will be removed from the menu. Existing completed bills are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) pos.deleteMenuItem(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    final availableCount = pos.menu.where((item) => item.isAvailable).length;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Menu Management'),
        actions: [
          IconButton(
            tooltip: 'Add dish',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openItemDialog(context, null),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                    boxShadow: AppTheme.elevationLow,
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(
                        Icons.restaurant_menu_rounded,
                        color: AppTheme.primary,
                      ),
                      Text(
                        '${pos.menu.length} dishes',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Container(width: 1, height: 20, color: AppTheme.border),
                      Text(
                        '$availableCount available',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (availableCount != pos.menu.length)
                        Text(
                          '${pos.menu.length - availableCount} sold out',
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: pos.menu.isEmpty
                    ? const Center(
                        child: Text(
                          'No dishes yet. Tap “Add Dish” to create your menu.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: pos.menu.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = pos.menu[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: item.isAvailable
                                    ? AppTheme.border
                                    : AppTheme.error.withValues(alpha: 0.25),
                              ),
                              boxShadow: AppTheme.elevationLow,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AppMenuImage(
                                    source: item.imageUrl,
                                    width: 62,
                                    height: 62,
                                    fit: BoxFit.cover,
                                    fallback: Container(
                                      width: 62,
                                      height: 62,
                                      color: AppTheme.primaryMuted,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.fastfood_rounded,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.category}  •  ₹${item.price.toStringAsFixed(item.price % 1 == 0 ? 0 : 2)}',
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        item.isAvailable
                                            ? 'AVAILABLE'
                                            : 'SOLD OUT',
                                        style: TextStyle(
                                          color: item.isAvailable
                                              ? AppTheme.success
                                              : AppTheme.error,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Tooltip(
                                  message: item.isAvailable
                                      ? 'Mark sold out'
                                      : 'Mark available',
                                  child: Switch.adaptive(
                                    value: item.isAvailable,
                                    onChanged: (value) =>
                                        pos.setMenuAvailability(item.id, value),
                                    activeTrackColor: AppTheme.success,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Dish actions',
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openItemDialog(context, item);
                                    } else if (value == 'delete') {
                                      _confirmDelete(context, pos, item);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('Edit'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.delete_outline,
                                          color: AppTheme.error,
                                        ),
                                        title: Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: AppTheme.error,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openItemDialog(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Dish'),
      ),
    );
  }
}

class _MenuItemEditorDialog extends StatefulWidget {
  final PosProvider pos;
  final MenuItem? existingItem;

  const _MenuItemEditorDialog({required this.pos, this.existingItem});

  @override
  State<_MenuItemEditorDialog> createState() => _MenuItemEditorDialogState();
}

class _MenuItemEditorDialogState extends State<_MenuItemEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _imageController;
  String? _category;
  String _selectedImage = '';

  List<String> get _categories =>
      widget.pos.categories.where((c) => c != 'All').toList();

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;
    _nameController = TextEditingController(text: item?.name ?? '');
    _priceController = TextEditingController(
      text: item == null
          ? ''
          : item.price.toStringAsFixed(item.price % 1 == 0 ? 0 : 2),
    );
    _imageController = TextEditingController(text: item?.imageUrl ?? '');
    _selectedImage = item?.imageUrl ?? '';

    final categories = _categories;
    if (item != null && categories.contains(item.category)) {
      _category = item.category;
    } else if (categories.isNotEmpty) {
      _category = categories.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create at least one menu category first.'),
        ),
      );
      return;
    }

    final price = double.parse(_priceController.text.trim());
    final typedImage = _imageController.text.trim();
    final imageUrl = _selectedImage.isNotEmpty
        ? _selectedImage
        : typedImage.isNotEmpty
        ? typedImage
        : 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=400';
    final existing = widget.existingItem;

    if (existing == null) {
      widget.pos.addMenuItem(
        MenuItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: _nameController.text.trim(),
          price: price,
          category: _category!,
          imageUrl: imageUrl,
        ),
      );
    } else {
      widget.pos.updateMenuItem(
        existing.id,
        _nameController.text.trim(),
        price,
        _category!,
        imageUrl,
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.existingItem == null ? 'Add Dish' : 'Edit Dish',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Dish name',
                    prefixIcon: Icon(Icons.restaurant_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a dish name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Selling price',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final price = double.tryParse(value?.trim() ?? '');
                    if (price == null || price <= 0) {
                      return 'Enter a valid price above ₹0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (categories.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'No categories available. Close this dialog and create a category first.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: categories
                        .map(
                          (category) => DropdownMenuItem<String>(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _category = value),
                    validator: (value) =>
                        value == null ? 'Select a category' : null,
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AppMenuImage(
                          source: _selectedImage.isNotEmpty
                              ? _selectedImage
                              : _imageController.text.trim(),
                          width: 82,
                          height: 82,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  final image = await pickLocalImageDataUrl();
                                  if (image != null && mounted) {
                                    setState(() {
                                      _selectedImage = image;
                                      _imageController.clear();
                                    });
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Choose from gallery'),
                            ),
                            if (_selectedImage.isNotEmpty)
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _selectedImage = ''),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('Remove selected photo'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _imageController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Or image URL (optional)',
                    prefixIcon: Icon(Icons.link_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: categories.isEmpty ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Dish'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 12: TEMPLATE & SOUNDBOX SETTINGS
// ============================================================================
class TemplateSettingsScreen extends StatefulWidget {
  const TemplateSettingsScreen({super.key});
  @override
  State<TemplateSettingsScreen> createState() => _TemplateSettingsScreenState();
}

class _TemplateSettingsScreenState extends State<TemplateSettingsScreen> {
  late TextEditingController nameCtrl;
  late TextEditingController taglineCtrl;
  late TextEditingController addressCtrl;
  late TextEditingController phoneCtrl;
  late List<TextEditingController> upiControllers;
  late TextEditingController footerCtrl;
  String soundboxLang = 'en-IN';
  String logoDataUrl = '';
  @override
  void initState() {
    super.initState();
    final template = Provider.of<PosProvider>(context, listen: false).template;
    nameCtrl = TextEditingController(text: template.storeName);
    taglineCtrl = TextEditingController(text: template.tagline);
    addressCtrl = TextEditingController(text: template.address);
    phoneCtrl = TextEditingController(text: template.phone);
    final initialUpiList = template.upiIds.isNotEmpty ? template.upiIds : ['friendstiffin@okaxis'];
    upiControllers = initialUpiList.map((id) => TextEditingController(text: id)).toList();
    footerCtrl = TextEditingController(text: template.footerMessage);
    soundboxLang = template.soundboxLanguage;
    logoDataUrl = template.logoDataUrl;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    taglineCtrl.dispose();
    addressCtrl.dispose();
    phoneCtrl.dispose();
    for (final c in upiControllers) {
      c.dispose();
    }
    footerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Store & Soundbox Setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: SwitchListTile(
              value: pos.isSoundboxEnabled,
              onChanged: (value) {
                pos.setSoundboxEnabled(value);
              },
              secondary: Icon(
                pos.isSoundboxEnabled
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: pos.isSoundboxEnabled
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
              ),
              title: const Text(
                'Sound Box',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                pos.isSoundboxEnabled
                    ? 'Voice payment alerts enabled'
                    : 'Off • payment alerts will stay silent',
              ),
              activeThumbColor: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Soundbox Spoken Alert Language',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: soundboxLang,
            decoration: const InputDecoration(
              labelText: 'Voice Language',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem<String>(
                value: 'en-IN',
                child: Text('English (Indian Accent)'),
              ),
              DropdownMenuItem<String>(
                value: 'ta-IN',
                child: Text('Tamil (தமிழ் அறிவிப்பு)'),
              ),
            ],
            onChanged: pos.isSoundboxEnabled
                ? (val) {
                    if (val != null) setState(() => soundboxLang = val);
                  }
                : null,
          ),
          const SizedBox(height: 20),
          const Text(
            'Store Branding',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AppMenuImage(
                    source: logoDataUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    fallback: Container(
                      width: 72,
                      height: 72,
                      color: AppTheme.primaryMuted,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: AppTheme.primary,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final image = await pickLocalImageDataUrl();
                            if (image != null && mounted) {
                              setState(() => logoDataUrl = image);
                            }
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceFirst('Exception: ', ''),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose restaurant logo'),
                      ),
                      if (logoDataUrl.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => logoDataUrl = ''),
                          child: const Text('Remove logo'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Printed Bill Branding',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Store Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: taglineCtrl,
            decoration: const InputDecoration(
              labelText: 'Tagline',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: addressCtrl,
            decoration: const InputDecoration(
              labelText: 'Store Address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Merchant UPI VPA IDs (Multiple Supported)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    upiControllers.add(TextEditingController());
                  });
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add UPI ID'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...upiControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final ctrl = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        labelText: 'UPI VPA ID #${idx + 1}',
                        hintText: 'e.g., merchant@okaxis',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (upiControllers.length > 1) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          upiControllers.removeAt(idx).dispose();
                        });
                      },
                      icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                      tooltip: 'Remove UPI ID',
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          TextField(
            controller: footerCtrl,
            decoration: const InputDecoration(
              labelText: 'Receipt Footer Message',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              final upiIdsList = upiControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
              if (upiIdsList.isEmpty) upiIdsList.add('friendstiffin@okaxis');

              Provider.of<PosProvider>(context, listen: false).updateTemplate(
                storeName: nameCtrl.text.trim(),
                tagline: taglineCtrl.text.trim(),
                address: addressCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                upiIds: upiIdsList,
                footer: footerCtrl.text.trim(),
                soundboxLang: soundboxLang,
                logoDataUrl: logoDataUrl,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings saved successfully!')),
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Configuration'),
          ),
        ],
      ),
    );
  }
} // ============================================================================

// SCREEN 13: BLUETOOTH THERMAL PRINTER SETUP
// ============================================================================
class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});
  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  List<BluetoothInfo> items = [];
  bool isScanning = false;
  bool _didInitialScan = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitialScan) {
      _didInitialScan = true;
      final pos = Provider.of<PosProvider>(context, listen: false);
      if (pos.isPrinterEnabled) {
        _scanPrinters();
      }
    }
  }

  Future<void> _scanPrinters() async {
    final pos = Provider.of<PosProvider>(context, listen: false);
    if (!pos.isPrinterEnabled || isScanning) return;
    setState(() => isScanning = true);

    try {
      await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ].request();
      final List<BluetoothInfo> list =
          await PrintBluetoothThermal.pairedBluetooths;
      if (!mounted) return;
      setState(() {
        items = list;
        isScanning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not scan paired Bluetooth printers on this device.',
          ),
        ),
      );
    }
  }

  Future<void> _connect(BluetoothInfo printer, PosProvider pos) async {
    try {
      final bool result = await PrintBluetoothThermal.connect(
        macPrinterAddress: printer.macAdress,
      );
      if (!mounted) return;
      if (result) {
        pos.setPrinterConnection(true, mac: printer.macAdress);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connected to ${printer.name}')));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect to ${printer.name}.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Printer connection failed. Check Bluetooth and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = Provider.of<PosProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Bluetooth Printers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: pos.isPrinterEnabled ? _scanPrinters : null,
          ),
        ],
      ),
      body: !pos.isPrinterEnabled
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.print_disabled_rounded,
                      size: 54,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Thermal printer is off',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Printing is disabled by default. Turn it on only when you want to pair or print receipts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () {
                        pos.setPrinterEnabled(true);
                        _scanPrinters();
                      },
                      icon: const Icon(Icons.power_settings_new_rounded),
                      label: const Text('Enable printer'),
                    ),
                  ],
                ),
              ),
            )
          : isScanning
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('No paired Bluetooth printers detected.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final printer = items[index];
                final isConnected =
                    pos.isPrinterConnected &&
                    pos.connectedPrinterMac == printer.macAdress;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.print,
                      color: isConnected ? AppTheme.primary : Colors.grey,
                    ),
                    title: Text(
                      printer.name.isEmpty ? 'POS Device' : printer.name,
                    ),
                    subtitle: Text(printer.macAdress),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected
                            ? Colors.grey
                            : AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: isConnected
                          ? null
                          : () => _connect(printer, pos),
                      child: Text(isConnected ? 'Connected' : 'Connect'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
