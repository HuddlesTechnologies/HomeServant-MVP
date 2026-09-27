import 'package:flutter/material.dart';
import '../api/models/chat.dart';

/// Renders the other participant's real profile photo (like every
/// mainstream chat app) when the API has one, falling back to a themed
/// icon otherwise — used anywhere a conversation's avatar is shown so a
/// "Landlord"/generic-person icon never stands in for an actual person.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.participant,
    required this.radius,
    required this.backgroundColor,
    required this.iconColor,
    this.icon = Icons.person,
  });

  final ThreadParticipant? participant;
  final double radius;
  final Color backgroundColor;
  final Color iconColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final photoUrl = participant?.profilePhotoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: NetworkImage(photoUrl),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(radius: radius, backgroundColor: backgroundColor, child: Icon(icon, color: iconColor, size: radius));
  }
}
