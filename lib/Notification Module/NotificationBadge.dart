import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationBadge extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool showCount;
  final Color badgeColor;
  final Color textColor;

  const NotificationBadge({
    super.key,
    required this.child,
    this.onTap,
    this.showCount = true,
    this.badgeColor = Colors.red,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return InkWell(
        onTap: onTap,
        child: child,
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              child,
              if (unreadCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: showCount
                        ? Text(
                      unreadCount > 99 ? '99+' : unreadCount.toString(),
                      style: GoogleFonts.poppins(
                        color: textColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Usage example widget for app bar
class NotificationIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final Color iconColor;

  const NotificationIconButton({
    super.key,
    required this.onPressed,
    this.icon = Icons.notifications,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationBadge(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(
          icon,
          color: iconColor,
          size: 24,
        ),
      ),
    );
  }
}