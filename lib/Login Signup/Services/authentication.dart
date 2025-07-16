import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthMethod {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // SignUp User
  Future<String> signupUser({
    required String email,
    required String password,
    required String name,
  }) async {
    String res = "Some error occurred";
    try {
      if (email.isNotEmpty && password.isNotEmpty && name.isNotEmpty) {
        // Create user in Firebase Authentication
        UserCredential cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );

        // Store user data in Firestore under users/{userId}/signupdetails/{docId}
        await _firestore
            .collection("users")
            .doc(cred.user!.uid)
            .collection("signupdetails")
            .doc("firstsignup") // Use a fixed doc ID for simplicity, e.g., "profile"
            .set({
          'name': name.trim(),
          'email': email.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        res = "success";
      } else {
        res = "Please fill all mandatory fields";
      }
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          res = 'This email is already registered.';
          break;
        case 'invalid-email':
          res = 'The email address is not valid.';
          break;
        case 'weak-password':
          res = 'The password is too weak.';
          break;
        default:
          res = 'Authentication error: ${e.message}';
      }
    } catch (err) {
      res = 'An error occurred: $err';
    }
    return res;
  }

  // LogIn User
  Future<String> loginUser({
    required String email,
    required String password,
  }) async {
    String res = "Some error occurred";
    try {
      if (email.isNotEmpty && password.isNotEmpty) {
        await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
        res = "success";
      } else {
        res = "Please enter all the fields";
      }
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          res = 'No user found for that email.';
          break;
        case 'wrong-password':
          res = 'Incorrect password.';
          break;
        case 'invalid-email':
          res = 'The email address is not valid.';
          break;
        default:
          res = 'Login error: ${e.message}';
      }
    } catch (err) {
      res = 'An error occurred: $err';
    }
    return res;
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (err) {
      throw Exception("Sign out failed: $err");
    }
  }
}