import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';
import 'package:tekartik_pick_crop_image_demo/src/import.dart';
import 'package:tekartik_pick_crop_image_demo/view/body_container.dart';
import 'package:tekartik_pick_crop_image_demo/view/body_padding.dart';

late SharedPreferences prefs;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pick Crop Image Demo',
      theme: ThemeData(
          // This is the theme of your application.
          //
          // Try running your application with "flutter run". You'll see the
          // application has a blue toolbar. Then, without quitting the app, try
          // changing the primarySwatch below to Colors.green and then invoke
          // "hot reload" (press "r" in the console where you ran "flutter run",
          // or simply save your changes to "hot reload" in a Flutter IDE).
          // Notice that the counter didn't reset back to zero; the application
          // is not restarted.
          // primarySwatch: Colors.blue,
          ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum AppImageSource { camera, gallery }

class _MyHomePageState extends State<MyHomePage> {
  final _isOpenPanels = ValueNotifier<List<bool>>(List<bool>.filled(4, false));
  final _result = ValueNotifier<PickCropImageResult?>(null);

  final _source = ValueNotifier<AppImageSource>(
      prefs.getString('source') == 'camera'
          ? AppImageSource.camera
          : AppImageSource.gallery);
  final _preferredCamera = ValueNotifier<CameraDevice>(
      prefs.getString('preferredCamera') == 'front'
          ? CameraDevice.front
          : CameraDevice.rear);
  @override
  void dispose() {
    _isOpenPanels.dispose();
    _source.dispose();
    _result.dispose();
    _preferredCamera.dispose();
    super.dispose();
  }

  void _onChangedSource(AppImageSource? source) {
    if (source != null) {
      _source.value = source;
      prefs.setString(
          'source', source == AppImageSource.camera ? 'camera' : 'gallery');
    }
  }

  void _onChangedPreferredCamera(CameraDevice? cameraDevice) {
    if (cameraDevice != null) {
      _preferredCamera.value = cameraDevice;
      prefs.setString('preferredCamera',
          cameraDevice == CameraDevice.front ? 'front' : 'rear');
      _onChangedSource(AppImageSource.camera);
    }
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: const Text('Pick Crop Image demo'),
      ),
      body: SingleChildScrollView(
        child: BodyContainer(
          child: Column(
            children: [
              const SizedBox(
                height: 16,
              ),
              ValueListenableBuilder<List<bool>>(
                  valueListenable: _isOpenPanels,
                  builder: (context, snapshot, _) {
                    var index = 0;
                    return BodyHPadding(
                      child: ExpansionPanelList(
                        expansionCallback: (int index, bool isExpanded) {
                          var list = List<bool>.from(_isOpenPanels.value);
                          list[index] = !isExpanded;
                          _isOpenPanels.value = list;
                        },
                        children: [
                          ExpansionPanel(
                            headerBuilder:
                                (BuildContext context, bool isExpanded) {
                              return ValueListenableBuilder<AppImageSource>(
                                  valueListenable: _source,
                                  builder: (context, source, _) {
                                    return ListTile(
                                      title: const Text('Image source'),
                                      subtitle: source == AppImageSource.camera
                                          ? ValueListenableBuilder<
                                                  CameraDevice>(
                                              valueListenable: _preferredCamera,
                                              builder: (context, camera, _) {
                                                return Text(
                                                    'Camera (${camera == CameraDevice.front ? 'front' : 'read'})');
                                              })
                                          : const Text('Gallery'),
                                    );
                                  });
                            },
                            body: ValueListenableBuilder<AppImageSource>(
                                valueListenable: _source,
                                builder: (context, source, _) {
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RadioListTile<AppImageSource>(
                                        title: const Text('Gallery'),
                                        value: AppImageSource.gallery,
                                        groupValue: source,
                                        onChanged: _onChangedSource,
                                      ),
                                      RadioListTile<AppImageSource>(
                                        title: const Text('Camera'),
                                        value: AppImageSource.camera,
                                        groupValue: source,
                                        onChanged: _onChangedSource,
                                      ),
                                      ValueListenableBuilder<CameraDevice>(
                                          valueListenable: _preferredCamera,
                                          builder: (context, camera, _) {
                                            return ValueListenableBuilder<
                                                    CameraDevice>(
                                                valueListenable:
                                                    _preferredCamera,
                                                builder: (context, camera, _) {
                                                  return Column(
                                                    children: [
                                                      RadioListTile<
                                                          CameraDevice>(
                                                        dense: true,
                                                        contentPadding:
                                                            const EdgeInsets
                                                                    .only(
                                                                left: 64,
                                                                right: 16),
                                                        title:
                                                            const Text('Rear'),
                                                        value:
                                                            CameraDevice.rear,
                                                        groupValue: camera,
                                                        onChanged:
                                                            _onChangedPreferredCamera,
                                                      ),
                                                      RadioListTile<
                                                          CameraDevice>(
                                                        dense: true,
                                                        contentPadding:
                                                            const EdgeInsets
                                                                    .only(
                                                                left: 64,
                                                                right: 16),
                                                        title:
                                                            const Text('Front'),
                                                        value:
                                                            CameraDevice.front,
                                                        groupValue: camera,
                                                        onChanged:
                                                            _onChangedPreferredCamera,
                                                      ),
                                                    ],
                                                  );
                                                });
                                          })
                                    ],
                                  );
                                }),
                            isExpanded: _isOpenPanels.value[index++],
                          )
                        ],
                      ),
                    );
                  }),
              ValueListenableBuilder<PickCropImageResult?>(
                  valueListenable: _result,
                  builder: (context, result, _) {
                    if (result != null) {
                      return Column(
                        children: [
                          const SizedBox(
                            height: 16,
                          ),
                          ElevatedButton(
                              onPressed: () {
                                saveImageFile(
                                    bytes: result.bytes,
                                    mimeType: result.encoding.mimeType,
                                    filename:
                                        'image${result.encoding.extension}');
                              },
                              child: const Text('Save image')),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.memory(
                                result.bytes,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Container();
                  }),
              const SizedBox(
                height: 64,
              ),
              FutureBuilder<String>(future: () async {
                var info = await PackageInfo.fromPlatform();
                return info.version.toString();
              }(), builder: (context, snapshot) {
                return ListTile(
                    title: Text(
                  snapshot.data ?? '',
                  style: TextStyle(color: Colors.grey[300]),
                ));
              })
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Pick and crop'),
        onPressed: () async {
          var imageSource = _source.value == AppImageSource.camera
              ? PickCropImageSourceCamera(
                  preferredCameraDevice: _preferredCamera.value)
              : const PickCropImageSourceGallery();
          print('imageSource: $imageSource');
          var result = await pickCropImage(context,
              options: PickCropImageOptions(
                  width: 1024, height: 1024, source: imageSource));
          if (result != null) {
            _result.value = result;
          }
        },
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
