// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025 Dogukan Mertoglu, Fabian Wiegandt

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";  // kDebugMode
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";  // PlatformException

import "package:camera/camera.dart" as camera;
import "package:csv/csv.dart" as csv;
import "package:flutter_platform_widgets/flutter_platform_widgets.dart" as platform_widgets;
import "package:flutter_secure_storage/flutter_secure_storage.dart" as secure_storage;
import "package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart" as mlkit_text_recognition;
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart" as path;
import "package:permission_handler/permission_handler.dart" as permission;
// import "package:provider/provider.dart" as provider;

const String locationListFilename = "locations.csv";
const String productListFilename = "products.csv";

// TODO: StoreDimensions should be configurable, but only one store is targeted right now
// Unit: centimeters
class StoreDimensions {
  // Notice that it says groundFloor and continuing, because the first floor corresponds to floor 1
  // american vs german floor counting
  static const int groundFloorWidth = 1800;  // cm (pointing south)
  static const int groundFloorHeight = 4200;  // cm (pointing west)
  static const int firstFloorWidth = 3100;  // cm (pointing east)
  static const int firstFloorHeight = 4500;  // cm (pointing south)
  static const int secondFloorWidth = 1000;  // cm
  static const int secondFloorHeight = 1000;  // cm
}

// TODO: Number of floors should be configurable, but only one store is targeted right now
enum Floor {
  ground,
  first,
  second,
}

@immutable
class Location {
  final int id;
  final Floor floor;
  final int x0;  // cm
  final int y0;  // cm
  final int a;  // cm
  final int b;  // cm

  const Location({
    required this.id,
    required this.floor,
    required this.x0,
    required this.y0,
    required this.a,
    required this.b,
  });

  List<int> toList() {
    return [id, floorToInt(floor), x0, y0, a, b];
  }

  @override
  String toString() {
    return "{id: $id, floor: $floor, x0: $x0, y0: $y0, a: $a, b: $b}";
  }
}

@immutable
class RackInfo {
  final int id;
  final Floor floor;
  final Rect rack;

  const RackInfo({
    required this.id,
    required this.floor,
    required this.rack,
  });

  @override
  String toString() {
    return "{id: $id, floor: $floor, rack: $rack}";
  }
}

@immutable
class Product {
  final String id;
  final int locationId;

  const Product({
    required this.id,
    required this.locationId,
  });

  List<String> toList() {
    return [id, locationId.toString()];
  }

  @override
  String toString() {
    return "{productId: $id, locationId: $locationId}";
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Directory appCacheDir = await path.getApplicationCacheDirectory();
  appCacheDir.createSync(recursive: true);
  print("Cache directory found");
  print("cache: $appCacheDir");

  // x0 and a are orthogonal to the entrance and y0 and b are parallel
  // In location.csv y0, y0, a and b are given in centimeters
  File locationListFile = File(getLocationListPath(appCacheDir));
  if (!locationListFile.existsSync() || true) {  // TODO: Remember to delete || true
    print("Location list file created");
    locationListFile.createSync(recursive: true, exclusive: false);  // TODO: Remember to change exclusive: true
    locationListFile.writeAsStringSync("id;floor;x0;y0;a;b");
  }

  File productListFile = File(getProductListPath(appCacheDir));
  if (!productListFile.existsSync() || true) {  // TODO: Remember to delete || true
    print("Product list file created");
    productListFile.createSync(recursive: true, exclusive: false);  // TODO: Remember to change exclusive: true
    productListFile.writeAsStringSync("product_id;location_id");
  }

  runApp(
    StoreLocateProduct(
      cacheDir: appCacheDir,
    ),
  );
}

int findLowestAvailableIndex(List<Location> locationList) {
  List<int> onlyIndexes = locationList
    .map((Location location) => location.id)
    .toList();
  onlyIndexes.sort((a, b) => a.compareTo(b));

  for (int i = 0; i < onlyIndexes.length; i++) {
    if(onlyIndexes[i] + 1 != onlyIndexes[i + 1]) {
      return onlyIndexes[i] + 1;
    }
  }
  return onlyIndexes[onlyIndexes.length - 1] + 1;
}

String getLocationListPath(Directory cacheDir) {
  return "${cacheDir.path}/$locationListFilename";
}

String getProductListPath(Directory cacheDir) {
  return "${cacheDir.path}/$productListFilename";
}

int floorToInt(Floor floor) {
  switch (floor) {
    case Floor.ground:
      return 0;
    case Floor.first:
      return 1;
    case Floor.second:
      return 2;
  }
}

Future<List<List<dynamic>>> readCsv(String path) async {
  final stream = File(path).openRead();
  return await stream
    .transform(utf8.decoder)
    .transform(csv.CsvToListConverter(fieldDelimiter: ";", eol: "\n"))
    .skip(1)
    .toList();
}

Future<List<Product>> readProductList(String path) async {
  final List<List<dynamic>> fields = await readCsv(path);
  return fields
    .map((List product) {
      int productId = product[0];
      String zeros = "";
      if (productId < 10) {
        zeros = "0" * 9;
      } else if (productId < 100) {
        zeros = "0" * 8;
      } else if (productId < 1_000) {
        zeros = "0" * 7;
      } else if (productId < 10_000) {
        zeros = "0" * 6;
      } else if (productId < 100_000) {
        zeros = "0" * 5;
      } else if (productId < 1_000_000) {
        zeros = "0" * 4;
      } else if (productId < 10_000_000) {
        zeros = "0" * 3;
      } else if (productId < 100_000_000) {
        zeros = "0" * 2;
      } else if (productId < 1_000_000_000) {
        zeros = "0" * 1;
      }
      return Product(id: "$zeros$productId", locationId: product[1]);
    })
    .toList();
}

Future<List<camera.CameraController>> initializeCamera() async {
  // Request camera permission before proceeding
  var status = await permission.Permission.camera.request();
  if (!status.isGranted) {
    return [];  // Return empty list so later on a length check instead of a null check can be done
  }

  List<camera.CameraDescription> cameras = await camera.availableCameras();
  if (cameras.isEmpty) {
    return [];  // Return empty list so later on a length check instead of a null check can be done
  }

  camera.CameraController controller = camera.CameraController(
    cameras[0],
    camera.ResolutionPreset.medium,
    enableAudio: false,
  );
  await controller.initialize();

  // await controller.setExposureMode(camera.ExposureMode.locked);
  // await controller.setFocusMode(camera.FocusMode.locked);

  return [controller];
}

class StoreLocateProduct extends StatelessWidget {
  final Directory cacheDir;

  const StoreLocateProduct({super.key, required this.cacheDir});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HM Wilma',
      theme: ThemeData(
        colorScheme: ColorScheme.dark(brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: HomePage(
        title: 'HM Wilma Locate Product',
        cacheDir: cacheDir,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String title;
  final Directory cacheDir;

  const HomePage({
    super.key,
    required this.title,
    required this.cacheDir,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _floors;
  bool locationsLoaded = false;
  bool productsLoaded = false;
  List<Location> locationList = [];
  List<Product> productList = [];
  int wantedLocationId = -1;
  String scannedBarcodeResult = "";

  @override
  void initState() {
    super.initState();
    _floors = TabController(length: 3, vsync: this);
  }

  Future<List<Location>> _loadLocations() async {
    final fields = await readCsv(getLocationListPath(widget.cacheDir));
    return fields
      .map((List location) {
        Floor floor = Floor.ground;
        switch (location[1]) {
          case 0:
            floor = Floor.ground;
          case 1:
            floor = Floor.first;
          case 2:
            floor = Floor.second;
          default:
            floor = Floor.ground;
        }
        return Location(
          id: location[0],
          floor: floor,
          x0: location[2].toInt(),
          y0: location[3].toInt(),
          a: location[4].toInt(),
          b: location[5].toInt(),
        );
      })
      .toList();
  }

  Future<List<Product>> _loadProducts() async {
    return await readProductList(getProductListPath(widget.cacheDir));
  }

  (int, Floor) _locateProduct(String productId) {
    int locationId = -1;
    for (Product product in productList) {
      if (product.id == productId) {
        locationId = product.locationId;
        break;
      }
    }
    Floor productFloor = Floor.ground;
    if (locationId == -1) return (locationId, productFloor);  // early return, because product couldn't be found
    for (Location location in locationList) {
      if (location.id == locationId) {
        productFloor = location.floor;
        break;
      }
    }
    return (locationId, productFloor);
  }

  Future<void> _downloadAndReplace() async {
    final String locationsCsvUrl = "https://pastebin.com/raw/MMruJhV9";
    final String productsPointerCsvUrl = "https://pastebin.com/raw/uZ4MzZdT";

    try {
      final response = await http.get(Uri.parse(locationsCsvUrl));
      if (response.statusCode == 200) {
        final file = File(getLocationListPath(widget.cacheDir));
        await file.writeAsString(response.body);
        if (kDebugMode) {
          print('Downloaded locations.csv and replaced');
        }
      }
    } catch (e) {
      print('Error downloading file: $e');
    }

    try {
      final responsePointer = await http.get(Uri.parse(productsPointerCsvUrl));
      if (responsePointer.statusCode == 200) {
        final response = await http.get(Uri.parse("https://pastebin.com/raw/${responsePointer.body}"));
        if (response.statusCode == 200) {
          final file = File(getProductListPath(widget.cacheDir));
          await file.writeAsString(response.body);
          if (kDebugMode) {
            print('Downloaded products.csv and replaced');
          }
        }
      }
    } catch (e) {
      print('Error downloading file: $e');
    }

  }

  @override
  Widget build(BuildContext context) {
    Widget searchBar = SearchAnchor(
      builder: (BuildContext context, SearchController controller) {
        return platform_widgets.PlatformIconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            controller.openView();
          },
        );
      },
      suggestionsBuilder: (BuildContext context, SearchController controller) {
        return List.empty(growable: true);
      },
      viewOnSubmitted: (String productId) {
        Navigator.of(context).maybePop();
        var (_wantedLocationId, floor) = _locateProduct(productId);
        _floors.animateTo(floorToInt(floor));
        setState(() {
          wantedLocationId = _wantedLocationId;
        });
      },
    );

    if (!locationsLoaded) {
      _loadLocations().then((List<Location> location) {
        setState(() {
          locationList = location;
          locationsLoaded = true;
        });
        if (kDebugMode) {
          print("Locations loaded");
          print(locationList);
        }
      });
    }

    if (!productsLoaded) {
      _loadProducts().then((List<Product> products) {
        setState(() {
          productList = products;
          productsLoaded = true;
        });
        if (kDebugMode) {
          print("Products loaded");
          print(productList);
        }
      });
    }

    List<Location> groundFloorLayoutList = locationList
      .where((Location location) => location.floor == Floor.ground)
      .toList();
    List<Location> firstFloorLayoutList = locationList
      .where((Location location) => location.floor == Floor.first)
      .toList();
    List<Location> secondFloorLayoutList = locationList
      .where((Location location) => location.floor == Floor.second)
      .toList();

    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        leading: platform_widgets.PlatformIconButton(
          icon: const Icon(Icons.settings),
          onPressed: () {
            Navigator.push(
              context,
              platform_widgets.platformPageRoute(
                context: context,
                builder: (context) => SettingsPage(
                  cacheDir: widget.cacheDir,
                ),
              ),
            );
          },
        ),
        actions: [
          platform_widgets.PlatformIconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await _downloadAndReplace();
              _loadLocations().then((List<Location> locations) {
                setState(() {
                  locationList = locations;
                });
              });
              _loadProducts().then((List<Product> products) {
                setState(() {
                  productList = products;
                });
              });
            },
          ),
          platform_widgets.PlatformIconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () async {
              List<camera.CameraController> cameraControllers = await initializeCamera();
              if (cameraControllers.length == 1) {
                camera.CameraController cameraController = cameraControllers[0];
                String productId = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TextRecognitionView(cameraController: cameraController),
                  ),
                );
                print("Found Product ID: ${productId}");
                var (_wantedLocationId, floor) = _locateProduct(productId);
                _floors.animateTo(floorToInt(floor));
                setState(() {
                  wantedLocationId = _wantedLocationId;
                });

              }
              // TODO: impl
            },
          ),
          searchBar
        ],
        bottom: TabBar(
          controller: _floors,
          tabs: [
            Tab(
              icon: Image.asset("assets/number-zero-fill-svgrepo-com.png"),
            ),
            Tab(
              icon: Image.asset("assets/number-one-fill-svgrepo-com.png"),
            ),
            Tab(
              icon: Image.asset("assets/number-two-fill-svgrepo-com.png"),
            ),
          ],
        ),
      ),
      body: locationsLoaded ? TabBarView(
        controller: _floors,
        children: <Widget>[
          FloorLayout(
            key: ValueKey(wantedLocationId + 0),
            floor: Floor.ground,
            locationList: groundFloorLayoutList,
            productList: productList,
            cacheDir: widget.cacheDir,
            wantedLocationId: wantedLocationId,
            productCallback: _loadProducts,
          ),
          FloorLayout(
            key: ValueKey(wantedLocationId + 1),
            floor: Floor.first,
            locationList: firstFloorLayoutList,
            productList: productList,
            cacheDir: widget.cacheDir,
            wantedLocationId: wantedLocationId,
            productCallback: _loadProducts,
          ),
          FloorLayout(
            key: ValueKey(wantedLocationId + 2),
            floor: Floor.second,
            locationList: secondFloorLayoutList,
            productList: productList,
            cacheDir: widget.cacheDir,
            wantedLocationId: wantedLocationId,
            productCallback: _loadProducts,
          ),
        ],
      ) : Text("Loading ..."),
    );
  }
}

class TextRecognitionView extends StatefulWidget {
  final camera.CameraController cameraController;

  const TextRecognitionView({required this.cameraController, Key? key}) : super(key: key);

  @override
  State<TextRecognitionView> createState() => _TextRecognitionViewState();
}

class _TextRecognitionViewState extends State<TextRecognitionView> {
  bool isProcessing = false;
  String recognizedText = "";
  bool isProductIdSuccessful = false;

  static const double captureButtonRelativeSize = 0.12;  // TODO: maybe adjust this value
  bool isCaptureButtonVisible = true;

  String _findProductId(mlkit_text_recognition.RecognizedText result) {
    for(mlkit_text_recognition.TextBlock block in result.blocks) {
      for (mlkit_text_recognition.TextLine line in block.lines) {
        for (int i = 0; i < line.elements.length; ++i) {
          mlkit_text_recognition.TextElement textElement = line.elements[i];
          // Zeros can be recognized as the letters 'O' or 'o'
          textElement.text.replaceAll("O", "0");
          textElement.text.replaceAll("o", "0");
          // Maybe we found the product id and the color code?
          if (textElement.text.length == 3 && i > 1 && line.elements[i-1].text.length == 7) {
            // Zeros can be recognized as the letters 'O' or 'o'
            line.elements[i-1].text.replaceAll("O", "0");
            line.elements[i-1].text.replaceAll("o", "0");
            // Are they parse-able as integers meaning they only consist of integers
            if (int.tryParse(textElement.text) != null && int.tryParse(line.elements[i-1].text) != null) {
              return "${line.elements[i-1].text} ${textElement.text}";
            }
          }
        }
      }
    }
    return "";
  }

  Future<void> captureAndRecognizeText() async {
    if (!widget.cameraController.value.isInitialized || isProcessing) return;

    setState(() {
      isProcessing = true;
    });

    try {
      camera.XFile imageFile = await widget.cameraController.takePicture();
      mlkit_text_recognition.InputImage inputImage = mlkit_text_recognition.InputImage.fromFilePath(imageFile.path);
      mlkit_text_recognition.TextRecognizer textRecognizer = mlkit_text_recognition.TextRecognizer();
      mlkit_text_recognition.RecognizedText result = await textRecognizer.processImage(inputImage);

      String foundProductId = _findProductId(result);

      setState(() {
        recognizedText = foundProductId.isNotEmpty ? foundProductId : "No Product ID found";
        if (foundProductId.isNotEmpty) {
          isProductIdSuccessful = true;
        }
      });

      textRecognizer.close();
    } catch (e) {
      setState(() {
        recognizedText = "Error: $e";
      });
    }

    setState(() {
      isProcessing = false;
    });
  }

  Future<void> failDialog() async {
    return await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('No Product ID was found'),
          content: const Text("No Product ID was recognized. You may try again"),
          actions: <Widget>[
            platform_widgets.PlatformTextButton(
              child: const Text("Return to camera"),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    if (widget.cameraController.value.isInitialized) {
      widget.cameraController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double captureButtonSize = screenHeight * captureButtonRelativeSize;
    double innerCircleSize = captureButtonSize * 0.6;  // TODO: maybe adjust this value

    return Scaffold(
      appBar: AppBar(
        title: const Text("Product ID Recognition"),
      ),
      body: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: widget.cameraController.value.aspectRatio,
              child: camera.CameraPreview(widget.cameraController),
            ),
          ),

          // TODO: switch this maybe to a floating button or a Stack so CameraView is the full screen
          SizedBox(
            height: captureButtonSize * 1.2, // TODO: switch this to 1.0
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.circle_outlined,
                      size: captureButtonSize,
                      color: Colors.white,
                    ),

                    GestureDetector(
                      onTapDown: (_) {
                        setState(() {
                          // TODO: maybe adjust this value
                          innerCircleSize = captureButtonSize * 0.5; // Shrink button on press
                        });
                      },
                      onTapUp: (_) async {
                        if (isProcessing) return;

                        setState(() {
                          // TODO: maybe adjust this value
                          innerCircleSize = captureButtonSize * 0.6; // Restore original size
                        });

                        await Future.delayed(Duration(milliseconds: 100), () {
                          setState(() {
                            isCaptureButtonVisible = false; // Briefly hide button after capture
                          });
                        });

                        await captureAndRecognizeText();
                        // TODO: send this to new_products.csv

                        await Future.delayed(Duration(milliseconds: 200), () {
                          setState(() {
                            isCaptureButtonVisible = true; // Show button again
                          });
                        });

                        if (isProductIdSuccessful) {
                          await showDialog<void>(
                            context: context,
                            barrierDismissible: true,
                            builder: (BuildContext dialogContext) {
                              return AlertDialog(
                                title: const Text("Product ID found"),
                                content: Text("Is $recognizedText correct?"),
                                actions: <Widget>[
                                  platform_widgets.PlatformTextButton(
                                    child: Text("Cancel"),
                                    onPressed: () {
                                      Navigator.of(dialogContext).pop();
                                    },
                                  ),
                                  platform_widgets.PlatformTextButton(
                                    child: Text("Submit"),
                                    onPressed: () {
                                      Navigator.of(dialogContext).pop();
                                      Navigator.of(context).pop(recognizedText);
                                    },
                                  ),
                                ],
                              );
                            },
                          );
                        } else {
                          await failDialog();
                        }
                        // Navigator.pop(context, recognizedText);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: innerCircleSize,
                        height: innerCircleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCaptureButtonVisible ? Colors.white : Colors.transparent,
                        ),
                      ),
                    ),
                  ]
                ),
                // TODO: delete Text() when debugging isn't necessary anymore
                Text(recognizedText, textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FloorLayout extends StatefulWidget {
  final Floor floor;
  final List<Location> locationList;
  final List<Product> productList;
  final Directory cacheDir;
  final int wantedLocationId;
  final Function productCallback;

  const FloorLayout({
    super.key,
    required this.floor,
    required this.locationList,
    required this.productList,
    required this.cacheDir,
    required this.wantedLocationId,
    required this.productCallback,
  });

  @override
  State<FloorLayout> createState() => _FloorLayoutState();
}

class _FloorLayoutState extends State<FloorLayout> {
  List<RackInfo> racks = [];

  Timer? _longPressTimer;
  bool _isLongPress = false;

  void onTapDown(TapDownDetails details) {
    Offset tapPosition = details.localPosition;
    _isLongPress = false;

    _longPressTimer = Timer(Duration(milliseconds: 500), () {
      _isLongPress = true;
      for (int i = 0; i < racks.length; i++) {
        if (racks[i].rack.contains(tapPosition)) {
          showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text("Deleting location"),
                content: const Text("Do you want to delete this location?"),
                actions: <Widget>[
                  platform_widgets.PlatformTextButton(
                    child: const Text("Cancel"),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                  platform_widgets.PlatformTextButton(
                    child: const Text("Delete"),
                    onPressed: () {
                      // TODO: impl
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
              );
            },
          );
        }
      }
    });
  }

  void onTapUp(TapUpDetails details) {
    if (!_isLongPress) {
      _longPressTimer?.cancel(); // Cleanup timer
      Offset tapPosition = details.localPosition;

      for (int i = 0; i < racks.length; i++) {
        if (racks[i].rack.contains(tapPosition)) {
          List<Product> productListFiltered = widget.productList
            .where(
              (Product product) => product.locationId == racks[i].id,
            )
            .toList();

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RackProductList(
                locationId: racks[i].id,
                productList: productListFiltered,
                cacheDir: widget.cacheDir,
                productCallback: widget.productCallback,
              ),
            ),
          );
          return;
        }
      }
    }
  }

  void onTapCancel() {
    _longPressTimer?.cancel();
  }

  // void onLongPressDown(LongPressDownDetails details) {
  //   Offset longTapPosition = details.localPosition;
  //
  //   _longPressTimer = Timer(Duration(milliseconds: 1000), () {
  //     for (int i = 0; i < racks.length; i++) {
  //       if(racks[i].rack.contains(longTapPosition)) {
  //         showDialog<void>(
  //           context: context,
  //           barrierDismissible: true,
  //           builder: (BuildContext dialogContext) {
  //             return AlertDialog(
  //               title: const Text("Deleting location"),
  //               content: const Text("Do you want to delete this location?"),
  //               actions: <Widget>[
  //                 TextButton(
  //                   child: const Text("Cancel"),
  //                   onPressed: () {
  //                     Navigator.of(dialogContext).pop();
  //                   },
  //                 ),
  //                 TextButton(
  //                   child: const Text("Delete"),
  //                   onPressed: () {
  //                     // TODO: impl
  //                     Navigator.of(dialogContext).pop();
  //                   },
  //                 ),
  //               ],
  //             );
  //           },
  //         );
  //       }
  //     }
  //   });
  //   return;
  // }

  @override
  Widget build(BuildContext context) {
    racks = widget.locationList
      .map((Location location) {
        // Converting into device specific measurements
        double deviceWidth = MediaQuery.sizeOf(context).width;
        double deviceHeight = MediaQuery.sizeOf(context).height;

        int realWidth = 1;
        int realHeight = 1;

        switch (widget.floor) {
          case Floor.ground: {
            realWidth = StoreDimensions.groundFloorWidth;
            realHeight = StoreDimensions.groundFloorHeight;
          }
          case Floor.first: {
            realWidth = StoreDimensions.firstFloorWidth;
            realHeight = StoreDimensions.firstFloorHeight;
          }
          case Floor.second: {
            realWidth = StoreDimensions.secondFloorWidth;
            realHeight = StoreDimensions.secondFloorHeight;
          }
        }
        // double[px] = double[px] * int[cm] / int[cm]
        double x0 = deviceWidth * location.x0 / realWidth;
        double y0 = deviceHeight * location.y0 / realHeight;
        double a = deviceWidth * location.a / realWidth;
        double b = deviceHeight * location.b / realHeight;

        return RackInfo(id: location.id, floor: widget.floor, rack: Rect.fromLTWH(x0, y0, a, b));
      })
      .toList();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GestureDetector(
        onTapDown: onTapDown,
        onTapUp: onTapUp,
        onTapCancel: onTapCancel,
        // onLongPressDown: onLongPressDown,
        child: CustomPaint(
          painter: RackPainter(racks: racks, wantedLocationId: widget.wantedLocationId),
          child: SizedBox.expand(), // Expands to fill the available space
        ),
      ),
    );
  }
}

class RackPainter extends CustomPainter {
  final List<RackInfo> racks;
  final int wantedLocationId;

  RackPainter({required this.racks, required this.wantedLocationId});

  @override
  void paint(Canvas canvas, Size size) {
    Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1; // TODO: Adjust strokeWidth if necessary

    for (var RackInfo(:id, :rack) in racks) {
      Color color = (id == wantedLocationId) ? Colors.red : Colors.grey;
      Paint fillPaint = Paint()
        ..color = color.withValues(alpha: 0.5);

      canvas.drawRect(rack, fillPaint);
      if ((id == wantedLocationId) || true) {
        canvas.drawRect(rack, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class FileNotifier extends ChangeNotifier {
  String _content = '';

  String get content => _content;

  void updateContent(String newContent) {
    _content = newContent;
    notifyListeners();
  }
}

class RackProductList extends StatefulWidget {
  final int locationId;
  final List<Product> productList;
  final Directory cacheDir;
  final Function productCallback;

  const RackProductList({
    super.key,
    required this.locationId,
    required this.productList,
    required this.cacheDir,
    required this.productCallback
  });

  @override
  State<RackProductList> createState() => _RackProductListState();
}

class _RackProductListState extends State<RackProductList> {
  List<String> literalDigits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"];

  Future<String> _showProductIdEntryDialog(BuildContext context) async {
    TextEditingController textController = TextEditingController(text: "");

    return await showDialog<String>(
      context: context,
      barrierDismissible: true, // false = user must tap button, true = tap outside dialog
      builder: (context) {
        return AlertDialog(
          title: const Text("Enter Product ID"),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: "..."),
          ),
          actions: <Widget>[
            platform_widgets.PlatformTextButton(
              onPressed: () {
                Navigator.pop(context, "");
              },
              child: const Text("Cancel"),
            ),
            platform_widgets.PlatformTextButton(
              onPressed: () => Navigator.pop(context, textController.text),
              child: const Text("Submit"),
            )
          ],
        );
      },
    ) ?? "";
  }

  void _addToNewProductList(String productId) {
    File newProductFile = File("${widget.cacheDir.path}/new_products.csv");
    if (!newProductFile.existsSync()) {
      newProductFile.createSync(exclusive: false);
      newProductFile.writeAsStringSync("product_id;location_id");
    }
    newProductFile.writeAsStringSync("\n$productId;${widget.locationId}", mode: FileMode.append);
  }

  bool _validateProductId(String productId) {
    bool digitsOnly = true;
    for (String char in productId.characters) {
      if (!literalDigits.contains(char)) {
        digitsOnly = false;
        break;
      }
    }
    return productId.length == 10 && digitsOnly;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Product List (ID: ${widget.locationId})"),
        actions: [
          platform_widgets.PlatformIconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () async {
              List<camera.CameraController> _cameraControllers = await initializeCamera();
              if (_cameraControllers.length > 0) {
                String productId = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) {
                      return TextRecognitionView(
                        cameraController: _cameraControllers[0],
                      );
                    },
                  ),
                );
              }
              // TODO: impl
            },
          ),
          platform_widgets.PlatformIconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              // Navigator.push(
              //   context,
              //   MaterialPageRoute(
              //     builder: (context) => AlertDialog(
              //       title: const Text("Enter Product ID"),
              //       content: TextField(
              //         controller: textController,
              //       ),
              //       actions: [
              //         TextButton(
              //           onPressed: () => Navigator.pop(context, ""),
              //           child: const Text("Cancel"),
              //         ),
              //         ElevatedButton(
              //           onPressed: () => Navigator.pop(context, textController.text),
              //           child: const Text("Submit"),
              //         ),
              //       ],
              //     ),
              //   ),
              // );

              String receivedProductId = await _showProductIdEntryDialog(context);
              if (_validateProductId(receivedProductId)) {
                _addToNewProductList(receivedProductId);
              }
              // TODO: impl
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: widget.productList.length,
        itemBuilder: (BuildContext context, int index) {
          String productId = widget.productList[index].id;
          return ListTile(
            title: Text("${productId.substring(0, 7)} ${productId.substring(7, 10)}"),
            trailing: platform_widgets.PlatformIconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                // TODO: impl
              },
            ),
          );
        }
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final Directory cacheDir;

  const SettingsPage({super.key, required this.cacheDir});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Actions"),
      ),
      body: ListView(
        children: [
          platform_widgets.PlatformTextButton(
            child: Text(
              "Update Product List",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UpdateProductsPage(
                    cacheDir: widget.cacheDir,
                  ),
                ),
              );
              // TODO: impl
            },
          ),
          platform_widgets.PlatformTextButton(
            child: Text(
              "API Key",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ApiKeyPage(),
                ),
              );
            },
          ),
          platform_widgets.PlatformTextButton(
            child: const Text(
              "Username & Password",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CredentialPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class UpdateProductsPage extends StatefulWidget {
  final Directory cacheDir;

  const UpdateProductsPage({super.key, required this.cacheDir});

  @override
  State<UpdateProductsPage> createState() => _UpdateProductsPageState();
}

class _UpdateProductsPageState extends State<UpdateProductsPage> {
  List<Product> newProductList = [];

  @override
  void initState() {
    super.initState();
    readProductList("${widget.cacheDir.path}/new_products.csv").then((List<Product> productList) {
      setState(() {
        newProductList = productList;
      });
    });
  }

  Future<String> _getUpdatedProductList() async {
    // This method assumes that the updated products are correct and products can only have one location
    // This means previous locations, even if true, will be overwritten
    List<Product> currentProductList = await readProductList(getProductListPath(widget.cacheDir));
    print("Original length: ${currentProductList.length}");

    Map<String, Product> currentProductMap = {for (Product product in currentProductList) product.id: product};
    print("New products length: ${currentProductMap.length}");

    for (Product product in newProductList) {
      currentProductMap[product.id] = product; // Overwrite if exists, add if new
    }
    currentProductList = currentProductMap.values.toList()
      ..sort((Product self, Product other) => self.locationId.compareTo(other.locationId));

    // for (int i = 0; i < currentProductList.length; i++) {
    //   if (currentProductMap.containsKey(currentProductList[i].id) &&
    //       newProductList.any((Product product) => product.id == currentProductList[i].id)) {
    //     currentProductList[i] = newProductList.firstWhere((Product product) => product.id == currentProductList[i].id);
    //   }
    // }
    //
    // currentProductList.addAll(newProductList.where((Product product) => !currentProductMap.containsKey(product.id)));
    // print("New length: ${currentProductList.length}");

    String newCsv = const csv.ListToCsvConverter().convert(
      currentProductList.map((Product product) => product.toList()).toList(),
      fieldDelimiter: ";",
      eol: "\n",
    );
    print(newCsv.substring(0, 50));
    return "product_id;location_id\n" + newCsv;
  }

  Future<void> _uploadNewProductsToPastebin() async {
    String apiDevKey = await SecureCredentialStorage.getApiKey();
    if (apiDevKey.length == 0) return;
    String apiUserKey = await SecureCredentialStorage.getUserKey();
    if (apiUserKey.length == 0) return;

    String newCsvProductList = await _getUpdatedProductList();

    // print(newCsvProductList);
    // return;

    final response = await http.post(
      Uri.parse("https://pastebin.com/api/api_post.php"),
      body: {
        "api_dev_key": apiDevKey,
        "api_option": "paste",
        "api_paste_code": newCsvProductList,
        "api_user_key": apiUserKey,
        "api_paste_name": "products.csv",
        "api_paste_private": "0",
        "api_paste_expire_date": "N",
        "api_folder_key": "HM-WILMA",
      }
    );

    if (response.statusCode == 200) {
      // TODO: delete old paste
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Product List"),
        actions: [
          platform_widgets.PlatformIconButton(
            icon: const Icon(Icons.upload),
            onPressed: () async {
              await _uploadNewProductsToPastebin();
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: newProductList.length,
        itemBuilder: (context, index) {
          Product productInfo = newProductList[index];
          return ListTile(
            title: Text(
              "${productInfo.id.substring(0, 7)} ${productInfo.id.substring(7, 10)}  |  ${productInfo.locationId}",
            ),
            // TODO: impl
          );
        },
      ),
    );
  }
}

class SecureCredentialStorage {
  static const _storage = secure_storage.FlutterSecureStorage();
  static const _apiKey = "pastebin_api_key";
  static const _usernameKey = "pastebin_user_key";
  static const _passwordKey = "pastebin_password_key";

  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _apiKey, value: apiKey);
  }

  static Future<String> getApiKey() async {
    return await _storage.read(key: _apiKey) ?? "";
  }

  static Future<void> savePassword(String password) async {
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<String> getPassword() async {
    return await _storage.read(key: _passwordKey) ?? "";
  }

  static Future<void> saveUsername(String username) async {
    await _storage.write(key: _usernameKey, value: username);
  }

  static Future<String> getUsername() async {
    return await _storage.read(key: _usernameKey) ?? "";
  }

  static Future<String> getUserKey() async {
    String apiDevKey = await getApiKey();
    if (apiDevKey.length == 0) return "";

    String username = await getUsername();
    if (username.length == 0) return "";

    String password = await getPassword();
    if (password.length == 0) return "";

    final response = await http.post(
      Uri.parse("https://pastebin.com/api/api_login.php"),
      body: {
        "api_dev_key": apiDevKey,
        "api_user_name": username,
        "api_user_password": password,
      },
    );

    if (response.statusCode == 200 && response.body.isNotEmpty) {
      return response.body;
    } else {
      return "";
    }
  }
}

class ApiKeyPage extends StatefulWidget {
  const ApiKeyPage({super.key});

  @override
  State<ApiKeyPage> createState() => _ApiKeyPageState();
}

class _ApiKeyPageState extends State<ApiKeyPage> {
  final TextEditingController _controller = TextEditingController();
  String _savedApiKey = "";
  bool _isObscure = true;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    String apiKey = await SecureCredentialStorage.getApiKey();
    setState(() {
      _savedApiKey = apiKey;
      _controller.text = apiKey;
    });
  }

  Future<void> _saveApiKey() async {
    await SecureCredentialStorage.saveApiKey(_controller.text);
    setState(() {
      _savedApiKey = _controller.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Pastebin API Key"),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              obscureText: _isObscure, // Hides API key
              controller: _controller,
              decoration: InputDecoration(
                labelText: "Enter Pastebin API Key",
                border: OutlineInputBorder(),
                suffixIcon: platform_widgets.PlatformIconButton(
                  icon: Icon(_isObscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () {
                    setState(() {
                      _isObscure = !_isObscure;
                    });
                  },
                )
              ),
            ),
            const SizedBox(height: 20),
            platform_widgets.PlatformElevatedButton(
              onPressed: _saveApiKey,
              child: const Text(
                "Save API Key",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _savedApiKey.length != 0 ? "API Key Saved Securely" : "No API Key Saved",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CredentialPage extends StatefulWidget {
  const CredentialPage({super.key});

  @override
  State<CredentialPage> createState() => _CredentialPageState();
}

class _CredentialPageState extends State<CredentialPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _savedUsername = "";
  String _savedPassword = "";
  bool _isUsernameObscure = true;
  bool _isPasswordObscure = true;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadPassword();
  }

  Future<void> _loadUsername() async {
    String username = await SecureCredentialStorage.getUsername();
    setState(() {
      _savedUsername = username;
      _usernameController.text = username;
    });
  }

  Future<void> _saveUsername() async {
    await SecureCredentialStorage.saveUsername(_usernameController.text);
    setState(() {
      _savedUsername = _usernameController.text;
    });
  }

  Future<void> _loadPassword() async {
    String password = await SecureCredentialStorage.getPassword();
    setState(() {
      _savedPassword = password;
      _passwordController.text = password;
    });
  }

  Future<void> _savePassword() async {
    await SecureCredentialStorage.savePassword(_passwordController.text);
    setState(() {
      _savedPassword = _passwordController.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pastebin Username And Password"),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              obscureText: _isUsernameObscure, // Hides API key
              controller: _usernameController,
              decoration: InputDecoration(
                  labelText: "Enter Pastebin Username",
                  border: OutlineInputBorder(),
                  suffixIcon: platform_widgets.PlatformIconButton(
                    icon: Icon(_isUsernameObscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() {
                        _isUsernameObscure = !_isUsernameObscure;
                      });
                    },
                  )
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              obscureText: _isPasswordObscure, // Hides API key
              controller: _passwordController,
              decoration: InputDecoration(
                  labelText: "Enter Pastebin Password",
                  border: OutlineInputBorder(),
                  suffixIcon: platform_widgets.PlatformIconButton(
                    icon: Icon(_isPasswordObscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() {
                        _isPasswordObscure = !_isPasswordObscure;
                      });
                    },
                  )
              ),
            ),
            const SizedBox(height: 20),
            platform_widgets.PlatformElevatedButton(
              onPressed: () {
                _saveUsername();
                _savePassword();
              },
              child: const Text(
                "Save Credentials",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _savedUsername.length != 0 ? "Username Saved Securely" : "No Username Saved",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _savedPassword.length != 0 ? "Password Saved Securely" : "No Password Saved",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
