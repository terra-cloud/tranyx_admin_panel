import 'package:firebase_core/firebase_core.dart';

enum Environment {
  development,
  staging,
  production;

  String get name => toString().split('.').last;
}

class FirebaseEnv {
  // Option configurations for the Admin-exclusive Firebase project (for Admin Auth and Hosting)
  static const FirebaseOptions adminOptions = FirebaseOptions(
    apiKey: "AIzaSyDmDFdlZCOBzDYx5EsZoy8Gw9mnBVtPNj0",
    authDomain: "tranyx-admin-portal.firebaseapp.com",
    projectId: "tranyx-admin-portal",
    storageBucket: "tranyx-admin-portal.firebasestorage.app",
    messagingSenderId: "998364264423",
    appId: "1:998364264423:web:f32052956a463360996f42",
  );

  // Option configurations for Development environment (tranyx-dev)
  static const FirebaseOptions devOptions = FirebaseOptions(
    apiKey: "AIzaSyDyIwtMC_ssjILT0tAdtLVf8M4qc7L3ijU",
    authDomain: "tranyx-dev.firebaseapp.com",
    projectId: "tranyx-dev",
    storageBucket: "tranyx-dev.firebasestorage.app",
    messagingSenderId: "709467070093",
    appId: "1:709467070093:web:4d38bcfda904b0d5df4cc4",
  );

  // Option configurations for Staging environment (tranyx-uat)
  static const FirebaseOptions stagingOptions = FirebaseOptions(
    apiKey: "AIzaSyCnIIBVASeoA7TiBUMdk-5_tNpooNdO42w",
    authDomain: "tranyx-uat.firebaseapp.com",
    projectId: "tranyx-uat",
    storageBucket: "tranyx-uat.firebasestorage.app",
    messagingSenderId: "108125328804",
    appId: "1:108125328804:web:f7ada108909ef0a5881d31",
  );

  // Option configurations for Production environment (tranyx-app)
  static const FirebaseOptions prodOptions = FirebaseOptions(
    apiKey: "AIzaSyAwy7lkwlhiSBCvtAoKyaeox2YKpKqD1hs",
    authDomain: "tranyx-app.firebaseapp.com",
    projectId: "tranyx-app",
    storageBucket: "tranyx-app.firebasestorage.app",
    messagingSenderId: "174332525079",
    appId: "1:174332525079:web:4ad05af27a88c4ba8f7a52",
  );

  /// Helper to get the correct options for an environment
  static FirebaseOptions optionsFor(Environment env) {
    switch (env) {
      case Environment.development:
        return devOptions;
      case Environment.staging:
        return stagingOptions;
      case Environment.production:
        return prodOptions;
    }
  }
}
