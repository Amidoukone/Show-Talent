import 'dart:convert'; // Import pour jsonEncode
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;

class PushNotificationService {

  // Fonction pour récupérer un token d'accès depuis Firebase
  static Future<String> getAccessToken() async {
    final serviceAccountJson = {
      // Authentification sécurisée
      "type": "service_account",
      "project_id": "show-talent-5987d",
      "private_key_id": "8595d95f57ab77bbbdf59c16b01a328892fcbfd1",
      "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC1caFAGEP+Bqpx\n/u+Tih3ie2DlHxJuXQoGWg7L4OQ7M/R7PfOqzHY4FNHDs1MS8Y3Pw31Z0PdGnXEP\nqVGLpuges6j8jT6hfYHfcZmBk34fSmo2wefkWw4hvhtTNTuiQQa5yiGywJX5nsX9\n1C8OVo7Wx7H37MO24s/hgvhstpzuSrwTFY3qHoNJSO6AJ4GeF52hNpTeCkmaLUOo\n/qvYI29sO/wjlwZnpELIooFz4qlzf6XWNr1/ciIOKfhKFQpvPKnSopXJTYQlyQ5a\nA++sHoVFhq2gAf3th2iza+acxHGqVxfRPEU2XOOWhNk0yqhfb3cxY17tsZvKTRAe\nmxrLD6cjAgMBAAECggEABXa6AdmZNo2R1WP1Z+55TugjN1MTtYIUurM8jdQkW0oJ\nuypW65ZDmxW5aVi9kCz49cAvxqQdxiEYlf2lyHxKsh374TsJn0hNwGJF2pqL6jpN\n738wUfaR+t8kKIHKXWzy3GZjVGQrP/yRfr7EefyOSZZy3AHjtN6onuRYQcHQAPbv\nHogkSB9wXrvLvQBe0RNriFx8IaCWJCIsCbIuDb4OcHL1le72ST/PKu1VcSY3cJ6V\nzXKMMYlGfFHojG/wvuQCkaRfiBLneJOny2oVroDFEJy9H/XJnz2N2tWfJFSIXf1v\n8pHzAqopifNITCF6+FkxixjNQCkM0X5FQ25DwGFmbQKBgQDDF+bmpSOYLJpZo4Yg\nZVFzoK8YL/5c9Fp3pzgSd34IAPZ2eGRfmujzFTX2BbrbOXokARc7lHd5mql3xjXT\nQ7WCVh7Y91a5GtWXZ3/x2EExqqHoiGuLafMc2UabCVhTxrD7D1GPWN6F/UR7EW7M\n8Ycpc17EVjv7XG7eMNn69KN7HwKBgQDuFtflTjn2cKdBize/VvfEdewmVmSunRd1\n9KVb1gb+aTWP7jEAaHJa9Kwfs3g4OmhMUbzF8csc/bsm5kPaggRnKJgUtiXPdKfK\nWPG4nHse48GV2UToje8WSvBwGRMrP1IQC0lD0989OB2BkAbxcFnSV49sONsBMZof\nzo2qz/tXfQKBgG7KyiQ9sCMhYV56kRcgssr5e7Y+uzNKyX2eByflmDsvYMgSwt3Q\neW5io0xeIKmS0JxVyj3ZqKf0fz034SVjFFc6VTZd8HAanyXmbzCG4S81edE2d+yq\ndJfzhDdTbUfWVHefUXAYxfZNyHAjjEry9xFBJZZWaqXq7kNcds4f1B99AoGBAMfh\nzabpIahPs1tHcanlbWU2Sud0qFof8E5K8XhEGuMDmMAZDHJ3PWo29zo2BbvO7TkF\ndiIIeKkCK1jhAB42AVRJtEPPF7cvDJ7IRUbjuEmalC8llMBYSFzC1VCG/JzWMCLg\nFsYm3cgbkEnxjKKt2/rHH9WPde1uoyII2s6IhU5RAoGAY9sbduqU3ahCwHpU/JLc\n8YzqblLMooGVDoXRf7HMyzTyCO+29JFOXv4RiZiuAsMBOvYjjSdJF1yThBHTOOI5\nLwsmgKI+UKFhu/gqLOnhcDU4SQcfO5AmDCX2YH7PZogAYItMLV8yfwdTcjHcDUIQ\nTXz1ZZ0fs+ncBI72SnGNDus=\n-----END PRIVATE KEY-----\n",
      "client_email": "show-talent-5987d@appspot.gserviceaccount.com",
      "client_id": "112862121141316193688",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/show-talent-5987d%40appspot.gserviceaccount.com",
      "universe_domain": "googleapis.com"
    };

    List<String> scopes = [
      'https://www.googleapis.com/auth/firebase.messaging',
      'https://www.googleapis.com/auth/userinfo.email'
    ];

    final client = await auth.clientViaServiceAccount(
      auth.ServiceAccountCredentials.fromJson(serviceAccountJson),
      scopes,
    );

    final credentials = await auth.obtainAccessCredentialsViaServiceAccount(
      auth.ServiceAccountCredentials.fromJson(serviceAccountJson),
      scopes,
      client,
    );

    client.close(); // Fermer le client

    return credentials.accessToken.data;
    }

  // Fonction pour envoyer la notification
  static Future<void> sendNotification({
    required String title,
    required String body,
    required String token,
    required String contextType,
    required String contextData,
  }) async {
    final String serverKey = await getAccessToken();
    final String firebaseMessagingEndpoint = 'https://fcm.googleapis.com/v1/projects/show-talent-5987d/messages:send';

    final Map<String, dynamic> notificationMessage = {
      'message': {
        'token': token,
        'notification': {
          'title': title,
          'body': body,
        },
        'data': {
          'type': contextType,
          'id': contextData,
        },
      }
    };

    // Convertir en chaîne JSON
    final String bodyJson = jsonEncode(notificationMessage);

    // Envoyer la requête POST avec la chaîne JSON dans le corps
    final response = await http.post(
      Uri.parse(firebaseMessagingEndpoint),
      headers: {
        'Authorization': 'Bearer $serverKey',
        'Content-Type': 'application/json',
      },
      body: bodyJson, // Le corps est maintenant au format JSON
    );

    if (response.statusCode == 200) {
      print('Notification envoyée avec succès.');
    } else {
      print('Erreur lors de l\'envoi de la notification : ${response.body}');
    }
  }
}