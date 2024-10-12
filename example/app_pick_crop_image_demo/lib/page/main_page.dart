import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tekartik_app_pick_crop_image_flutter/pick_crop_image.dart';
import 'package:tekartik_pick_crop_image_demo/main.dart';
import 'package:tekartik_pick_crop_image_demo/src/import.dart';
import 'package:tekartik_pick_crop_image_demo/view/body_container.dart';
import 'package:tekartik_pick_crop_image_demo/view/body_padding.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  @override
  State<MainPage> createState() => _MainPageState();
}

enum AppImageSource { camera, gallery, memory }

class _MainPageState extends State<MainPage> {
  final _isOpenPanels = ValueNotifier<List<bool>>(List<bool>.filled(4, false));
  final _result = ValueNotifier<ImageData?>(null);
  final _ovalCropMask =
      ValueNotifier<bool>(prefs.getBool('ovalCropMask') ?? false);
  final _ovalCropInPreview =
      ValueNotifier<bool>(prefs.getBool('ovalCropInPreview') ?? true);
  final _width = ValueNotifier<int?>(prefs.getInt('width'));
  final _height = ValueNotifier<int?>(prefs.getInt('height'));

  final _source = ValueNotifier<AppImageSource>(() {
    var source = prefs.getString('source');
    if (source == 'camera') {
      return AppImageSource.camera;
    } else if (source == 'memory') {
      return AppImageSource.memory;
    }
    return AppImageSource.gallery;
  }());

  final _preferredCamera = ValueNotifier<SourceCameraDevice>(
      prefs.getString('preferredCamera') == 'front'
          ? SourceCameraDevice.front
          : SourceCameraDevice.rear);
  late TextEditingController _widthController;
  late TextEditingController _heightController;

  @override
  void dispose() {
    _isOpenPanels.dispose();
    _source.dispose();
    _result.dispose();
    _preferredCamera.dispose();
    _ovalCropMask.dispose();
    _ovalCropInPreview.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  @override
  void initState() {
    _widthController = TextEditingController(text: _width.value?.toString());
    _heightController = TextEditingController(text: _height.value?.toString());
    super.initState();
  }

  void _onChangedSource(AppImageSource? source) {
    if (source != null) {
      _source.value = source;
      late String text;
      if (source == AppImageSource.camera) {
        text = 'camera';
      } else if (source == AppImageSource.memory) {
        text = 'memory';
      } else {
        text = 'gallery';
      }
      prefs.setString('source', text);
    }
  }

  void _onChangedPreferredCamera(SourceCameraDevice? cameraDevice) {
    if (cameraDevice != null) {
      _preferredCamera.value = cameraDevice;
      prefs.setString('preferredCamera',
          cameraDevice == SourceCameraDevice.front ? 'front' : 'rear');
      _onChangedSource(AppImageSource.camera);
    }
  }

  void _onOvalCropMask(bool ovalCropMask) {
    _ovalCropMask.value = ovalCropMask;
    prefs.setBool('ovalCropMask', ovalCropMask);
  }

  void _onOvalCropInPreview(bool ovalCropInPreview) {
    _ovalCropInPreview.value = ovalCropInPreview;
    prefs.setBool('ovalCropInPreview', ovalCropInPreview);
  }

  void _setIntPrefs(String key, int? value) {
    if (value == null) {
      prefs.remove(key);
    } else {
      prefs.setInt(key, value);
    }
  }

  int? _saveWidth() {
    var width = int.tryParse(_widthController.text);
    _setIntPrefs('width', width);
    _width.value = width;
    return width;
  }

  int? _saveHeight() {
    var height = int.tryParse(_heightController.text);
    _setIntPrefs('height', height);
    _height.value = height;
    return height;
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
              buildOptions(),
              ValueListenableBuilder<ImageData?>(
                  valueListenable: _result,
                  builder: (context, result, _) {
                    if (result != null) {
                      return Column(
                        children: [
                          const SizedBox(
                            height: 16,
                          ),
                          BodyHPadding(
                            child: Row(
                              children: [
                                Text(
                                    '${result.width}x${result.height}, ${result.bytes.length} bytes, ${result.encoding.mimeType}'),
                                Expanded(child: Container()),
                                ElevatedButton(
                                    onPressed: () {
                                      saveImageFile(
                                          bytes: result.bytes,
                                          mimeType: result.encoding.mimeType,
                                          filename:
                                              'image${result.encoding.extension}');
                                    },
                                    child: const Text('Save image')),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: ValueListenableBuilder<bool>(
                                  valueListenable: _ovalCropMask,
                                  builder: (context, ovalCropMask, _) {
                                    return ValueListenableBuilder<bool>(
                                        valueListenable: _ovalCropInPreview,
                                        builder:
                                            (context, ovalCropInPreview, _) {
                                          Widget image = AspectRatio(
                                              aspectRatio:
                                                  result.width / result.height,
                                              child: Image.memory(
                                                result.bytes,
                                                fit: BoxFit.contain,
                                              ));
                                          if (ovalCropInPreview &&
                                              ovalCropMask) {
                                            image = ClipOval(
                                              child: image,
                                            );
                                          }
                                          return image;
                                        });
                                  }),
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
                  style: TextStyle(
                      color: Colors.grey[300],
                      fontStyle: FontStyle.italic,
                      fontSize: 12),
                ));
              })
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Pick and crop'),
        onPressed: () => _onPickAndCrop(context),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  Future<void> _onPickAndCrop(BuildContext context) async {
    var source = _source.value;
    late PickCropImageSource imageSource;
    if (source == AppImageSource.camera) {
      imageSource = PickCropImageSourceCamera(
          preferredCameraDevice: _preferredCamera.value);
    } else if (source == AppImageSource.memory) {
      imageSource = PickCropImageSourceMemory(
          bytes: byteDataToUint8List(
              await rootBundle.load('assets/img/image_example.jpg')));
    } else {
      imageSource = const PickCropImageSourceGallery();
    }

    // print('imageSource: $imageSource');
    var width = _saveWidth();
    var height = _saveHeight();
    var ovalCropMask = _ovalCropMask.value;
    // print('width $width, height $height, cropOvalMask $ovalCropMask');

    // ignore: use_build_context_synchronously
    var result = await pickCropImage(context,
        options: PickCropImageOptions(
            width: width,
            height: height,
            source: imageSource,
            ovalCropMask: ovalCropMask));
    // print('result: $result');
    if (result != null) {
      _result.value = result;
    }
  }

  ValueListenableBuilder<List<bool>> buildOptions() {
    return ValueListenableBuilder<List<bool>>(
        valueListenable: _isOpenPanels,
        builder: (context, snapshot, _) {
          var index = 0;
          return BodyHPadding(
            child: ExpansionPanelList(
              expansionCallback: (int index, bool isExpanded) {
                var list = List<bool>.from(_isOpenPanels.value);
                list[index] = isExpanded;
                _isOpenPanels.value = list;
              },
              children: [
                ExpansionPanel(
                  headerBuilder: (BuildContext context, bool isExpanded) {
                    return ValueListenableBuilder<AppImageSource>(
                        valueListenable: _source,
                        builder: (context, source, _) {
                          return ListTile(
                            title: const Text('Image source'),
                            subtitle: source == AppImageSource.camera
                                ? ValueListenableBuilder<SourceCameraDevice>(
                                    valueListenable: _preferredCamera,
                                    builder: (context, camera, _) {
                                      return Text(
                                          'Camera (${camera == SourceCameraDevice.front ? 'front' : 'rear'})');
                                    })
                                : (source == AppImageSource.memory)
                                    ? const Text('Memory')
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
                            ValueListenableBuilder<SourceCameraDevice>(
                                valueListenable: _preferredCamera,
                                builder: (context, camera, _) {
                                  return ValueListenableBuilder<
                                          SourceCameraDevice>(
                                      valueListenable: _preferredCamera,
                                      builder: (context, camera, _) {
                                        return Column(
                                          children: [
                                            RadioListTile<SourceCameraDevice>(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.only(
                                                      left: 64, right: 16),
                                              title: const Text('Rear'),
                                              value: SourceCameraDevice.rear,
                                              groupValue: camera,
                                              onChanged:
                                                  _onChangedPreferredCamera,
                                            ),
                                            RadioListTile<SourceCameraDevice>(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.only(
                                                      left: 64, right: 16),
                                              title: const Text('Front'),
                                              value: SourceCameraDevice.front,
                                              groupValue: camera,
                                              onChanged:
                                                  _onChangedPreferredCamera,
                                            ),
                                          ],
                                        );
                                      });
                                }),
                            RadioListTile<AppImageSource>(
                              title: const Text('Memory'),
                              value: AppImageSource.memory,
                              groupValue: source,
                              onChanged: _onChangedSource,
                            ),
                          ],
                        );
                      }),
                  isExpanded: _isOpenPanels.value[index++],
                ),
                ExpansionPanel(
                  headerBuilder: (BuildContext context, bool isExpanded) {
                    return ValueListenableBuilder<int?>(
                        valueListenable: _width,
                        builder: (context, width, _) {
                          return ValueListenableBuilder<int?>(
                              valueListenable: _height,
                              builder: (context, height, _) {
                                return ValueListenableBuilder<bool>(
                                    valueListenable: _ovalCropMask,
                                    builder: (context, ovalCropMask, _) {
                                      var sb = StringBuffer();
                                      if (width != null && height != null) {
                                        sb.write('${width}x$height');
                                      } else if (width != null) {
                                        sb.write('width: $width');
                                      } else if (height != null) {
                                        sb.write('height: $height');
                                      }
                                      if (ovalCropMask) {
                                        if (sb.isNotEmpty) {
                                          sb.write(', ');
                                          sb.write(' oval');
                                        }
                                      }

                                      return ListTile(
                                        title: const Text('Options'),
                                        subtitle: Text(sb.toString()),
                                      );
                                    });
                              });
                        });
                  },
                  body: ValueListenableBuilder<AppImageSource>(
                      valueListenable: _source,
                      builder: (context, source, _) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              height: 8,
                            ),
                            BodyHPadding(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                        controller: _widthController,
                                        keyboardType: TextInputType.number,
                                        onSubmitted: (text) {
                                          _saveWidth();
                                        },
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          labelText: 'Width',
                                        )),
                                  ),
                                  const SizedBox(
                                    width: 8,
                                  ),
                                  const Text('x'),
                                  const SizedBox(
                                    width: 8,
                                  ),
                                  Expanded(
                                    child: TextField(
                                        controller: _heightController,
                                        keyboardType: TextInputType.number,
                                        onSubmitted: (text) {
                                          _saveHeight();
                                        },
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          labelText: 'Height',
                                        )),
                                  ),
                                ],
                              ),
                            ),
                            ValueListenableBuilder<bool>(
                                valueListenable: _ovalCropMask,
                                builder: (context, ovalCropMask, _) {
                                  return Column(
                                    children: [
                                      SwitchListTile(
                                        value: ovalCropMask,
                                        onChanged: (value) {
                                          _onOvalCropMask(value);
                                        },
                                        title: const Text('Oval crop mask'),
                                      ),
                                      ValueListenableBuilder<bool>(
                                          valueListenable: _ovalCropInPreview,
                                          builder:
                                              (context, ovalCropInPreview, _) {
                                            return SwitchListTile(
                                              contentPadding:
                                                  const EdgeInsets.only(
                                                      left: 64, right: 16),
                                              value: ovalCropInPreview,
                                              onChanged: ovalCropMask
                                                  ? (value) {
                                                      _onOvalCropInPreview(
                                                          value);
                                                    }
                                                  : null,
                                              title: const Text(
                                                  'Crop in preview result'),
                                            );
                                          }),
                                    ],
                                  );
                                })
                          ],
                        );
                      }),
                  isExpanded: _isOpenPanels.value[index++],
                )
              ],
            ),
          );
        });
  }
}
