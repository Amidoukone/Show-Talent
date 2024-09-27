
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:show_talent/controller/notification_controller.dart';

class NotificationsScreen extends StatelessWidget {
  final NotificationController notificationController = Get.put(NotificationController());

 NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Obx(() {
        if (notificationController.notifications.isEmpty) {
          return const Center(child: Text('Aucune notification disponible.'));
        } else {
          return ListView.builder(
            itemCount: notificationController.notifications.length,
            itemBuilder: (context, index) {
              final notification = notificationController.notifications[index];

              return ListTile(
                title: Text(notification.message),
                subtitle: Text(notification.type),
                trailing: notification.estLue
                    ? const Icon(Icons.done, color: Colors.green)
                    : const Icon(Icons.new_releases, color: Colors.red),
                onTap: () {
                  // Action quand une notification est cliquée
                  notificationController.markAsRead(notification.id);
                },
              );
            },
          );
        }
      }),
    );
  }
}
