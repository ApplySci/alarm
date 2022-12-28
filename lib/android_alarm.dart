// ignore_for_file: avoid_print

import 'dart:isolate';
import 'dart:ui';

import 'package:alarm/notification.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:just_audio/just_audio.dart';

class AndroidAlarm {
  static const int alarmId = 888;
  static String ringPort = 'alarm-ring';
  static String stopPort = 'alarm-stop';

  static Future<void> init() => AndroidAlarmManager.initialize();

  static Future<bool> set(
    DateTime alarmDateTime,
    void Function()? onRing,
    String assetAudioPath,
    bool loopAudio,
    String? notifTitle,
    String? notifBody,
  ) async {
    try {
      final ReceivePort port = ReceivePort();
      final success =
          IsolateNameServer.registerPortWithName(port.sendPort, ringPort);

      if (!success) {
        IsolateNameServer.removePortNameMapping(ringPort);
        IsolateNameServer.registerPortWithName(port.sendPort, ringPort);
      }
      port.listen((message) {
        print("[Alarm] (main) received: $message");
        if (message == 'ring') onRing?.call();
      });
    } catch (e) {
      print("[Alarm] (main) ReceivePort error: $e");
      return false;
    }

    final res = await AndroidAlarmManager.oneShotAt(
      alarmDateTime,
      alarmId,
      AndroidAlarm.playAlarm,
      alarmClock: true,
      allowWhileIdle: true,
      exact: true,
      rescheduleOnReboot: true,
      params: {
        "assetAudioPath": assetAudioPath,
        "loopAudio": loopAudio,
        "notifTitle": notifTitle,
        "notifBody": notifBody,
      },
    );
    return res;
  }

  @pragma('vm:entry-point')
  static Future<void> playAlarm(int id, Map<String, dynamic> data) async {
    final audioPlayer = AudioPlayer();
    SendPort send = IsolateNameServer.lookupPortByName(ringPort)!;

    send.send('ring');

    try {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse("asset:///assets/${data["assetAudioPath"]}"),
        ),
      );

      final loopAudio = data["loopAudio"] ?? false;
      if (loopAudio) audioPlayer.setLoopMode(LoopMode.all);

      audioPlayer.play();
      send.send('[Alarm] Alarm playing...');
    } catch (e) {
      send.send('[Alarm] AudioPlayer error: $e');
    }

    final notifTitle = data["notifTitle"];
    final notifBody = data["notifBody"];
    if (notifTitle != null && notifBody != null) {
      await Notification.instance
          .androidAlarmNotif(title: "title", body: "body");
    }

    try {
      final ReceivePort port = ReceivePort();
      final success =
          IsolateNameServer.registerPortWithName(port.sendPort, stopPort);

      if (!success) {
        IsolateNameServer.removePortNameMapping(stopPort);
        IsolateNameServer.registerPortWithName(port.sendPort, stopPort);
      }

      port.listen(
        (message) async {
          send.send("[AndroidAlarm] (isolate) received: $message");
          if (message == 'stop') {
            await audioPlayer.stop();
            await audioPlayer.dispose();
            port.close();
          }
        },
      );
    } catch (e) {
      send.send("[AndroidAlarm] (isolate) ReceivePort error: $e");
    }
  }

  static Future<bool> stop() async {
    try {
      final SendPort send = IsolateNameServer.lookupPortByName(stopPort)!;
      print("[AndroidAlarm] (main) send stop to isolate");
      send.send('stop');
    } catch (e) {
      print("[AndroidAlarm] (main) SendPort error: $e");
    }

    final res = await AndroidAlarmManager.cancel(alarmId);
    // Storage.setAppLocalData("androidAlarm", false);

    return res;
  }

  static Future<void> ring() async {
    print("[Alarm] ring callback");
  }
}