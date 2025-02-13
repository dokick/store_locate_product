// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2025 Dogukan Mertoglu, Fabian Wiegandt

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";  // kDebugMode
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";  // PlatformException

import "package:csv/csv.dart" as csv;
// import "package:dartframe/dartframe.dart" as df;
// import "package:flutter_barcode_scanner/flutter_barcode_scanner.dart" as barcode;
import "package:flutter_platform_widgets/flutter_platform_widgets.dart" as platform_widgets;
import "package:flutter_secure_storage/flutter_secure_storage.dart" as secure_storage;
import "package:http/http.dart" as http;
import "package:mobile_scanner/mobile_scanner.dart" as scanner;
import "package:path_provider/path_provider.dart" as path;
import "package:permission_handler/permission_handler.dart" as permission;
import "package:provider/provider.dart" as provider;

// Unit: centimeters
class StoreDimensions {
  // Notice that it says groundFloor and continuing, because the first floor corresponds to floor 1
  // american vs german floor counting
  static const int groundFloorWidth = 1700;  // cm (pointing south)
  static const int groundFloorHeight = 4000;  // cm (pointing west)
  static const int firstFloorWidth = 3100;  // cm (pointing east)
  static const int firstFloorHeight = 4500;  // cm (pointing south)
  static const int secondFloorWidth = 1000;  // cm
  static const int secondFloorHeight = 1000;  // cm
}

enum Floor {
  ground,
  first,
  second,
}

@immutable
class LayoutInfo {
  final int id;
  final Floor floor;
  final int x0;  // cm
  final int y0;  // cm
  final int a;  // cm
  final int b;  // cm

  const LayoutInfo({
    required this.id,
    required this.floor,
    required this.x0,
    required this.y0,
    required this.a,
    required this.b,
  });

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
class ProductInfo {
  final String productId;
  final int locationId;

  const ProductInfo({
    required this.productId,
    required this.locationId,
  });

  @override
  String toString() {
    return "{productId: $productId, layoutId: $locationId}";
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Directory appCacheDir = await path.getApplicationCacheDirectory();
  appCacheDir.createSync(recursive: true);
  Directory configDir = Directory("${appCacheDir.path}/config");
  configDir.createSync(recursive: true);
  print("Cache directory found");
  print("config: $configDir");

  // x0 and a are orthogonal to the entrance and y0 and b are parallel
  // In layout.csv y0, y0, a and b are given in centimeters
  File layoutFile = File("${configDir.path}/locations.csv");
  if (!layoutFile.existsSync() || true) {  // TODO: Remember to delete || true
    print("Layout file created");
    layoutFile.createSync(recursive: true, exclusive: false);  // TODO: Remember to change exclusive: true
    layoutFile.writeAsStringSync("id;floor;x0;y0;a;b");
  }

  File productFile = File("${configDir.path}/products.csv");
  if (!productFile.existsSync() || true) {  // TODO: Remember to delete || true
    print("Product file created");
    productFile.createSync(recursive: true, exclusive: false);  // TODO: Remember to change exclusive: true
    productFile.writeAsStringSync("product_id;location_id");
  }

  runApp(
    provider.ChangeNotifierProvider(
      create: (context) => FileNotifier(),
      child: StoreLocateProduct(
        layoutPath: layoutFile.path,
        productPath: productFile.path,
      ),
    )
  );
}

int findLowestAvailableIndex(List<LayoutInfo> layoutList) {
  List<int> onlyIndexes = layoutList
    .map((LayoutInfo layout) => layout.id)
    .toList();
  onlyIndexes.sort((a, b) => a.compareTo(b));

  for (int i = 0; i < onlyIndexes.length; i++) {
    if(onlyIndexes[i] + 1 != onlyIndexes[i + 1]) {
      return onlyIndexes[i] + 1;
    }
  }
  return onlyIndexes[onlyIndexes.length - 1] + 1;
}

class StoreLocateProduct extends StatelessWidget {
  final String layoutPath;
  final String productPath;

  const StoreLocateProduct({super.key, required this.layoutPath, required this.productPath});

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
        layoutPath: layoutPath,
        productPath: productPath,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String title;
  final String layoutPath;
  final String productPath;

  const HomePage({
    super.key,
    required this.title,
    required this.layoutPath,
    required this.productPath,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _floors;
  bool locationsLoaded = false;
  bool productsLoaded = false;
  List<LayoutInfo> locationList = [];
  List<ProductInfo> productList = [];
  int wantedLocationId = -1;
  String scannedBarcodeResult = "";

  scanner.Barcode? _barcode;

  @override
  void initState() {
    super.initState();
    _floors = TabController(length: 3, vsync: this);
  }

  // TODO: Consider switching to dartframe https://pub.dev/packages/dartframe

  Future<List<LayoutInfo>> _loadLayout() async {
    final stream = File(widget.layoutPath).openRead();
    final fields = await stream
      .transform(utf8.decoder)
      .transform(csv.CsvToListConverter(fieldDelimiter: ";", eol: "\n"))
      .skip(1)
      .map((List layout) {
        Floor floor = Floor.ground;
        switch (layout[1]) {
          case 0:
            floor = Floor.ground;
          case 1:
            floor = Floor.first;
          case 2:
            floor = Floor.second;
          default:
            floor = Floor.ground;
        }
        return LayoutInfo(
          id: layout[0],
          floor: floor,
          x0: layout[2].toInt(),
          y0: layout[3].toInt(),
          a: layout[4].toInt(),
          b: layout[5].toInt(),
        );
      })
      .toList();
    if (kDebugMode) {
      print("Inside of loadLayout: $fields");
    }
    // print(fields[0].x0);
    // print(fields[0].x0.runtimeType);
    // print(fields[0].y0);
    // print(fields[0].y0.runtimeType);
    return fields;
  }

  Future<List<ProductInfo>> _loadProducts() async {
    final stream = File(widget.productPath).openRead();
    final fields = await stream
      .transform(utf8.decoder)
      .transform(csv.CsvToListConverter(fieldDelimiter: ";", eol: "\n"))
      .skip(1)
      .toList();
    if (kDebugMode) {
      print("Raw: $fields");
    }
    // print(fields[0][0].runtimeType);
    // print(fields[0][1].runtimeType);
    List<ProductInfo> zeroPaddedFields = fields
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
        return ProductInfo(productId: "$zeros$productId", locationId: product[1]);
      })
      .toList();
    return zeroPaddedFields;
  }

  (int, Floor) _locateProduct(String productId) {
    int locationId = -1;
    for (ProductInfo product in productList) {
      if (product.productId == productId) {
        locationId = product.locationId;
        break;
      }
    }
    Floor productFloor = Floor.ground;
    for (LayoutInfo location in locationList) {
      if (location.id == locationId) {
        productFloor = location.floor;
        break;
      }
    }
    return (locationId, productFloor);
  }

  Future<void> _downloadAndReplace() async {
    final locationsCsvUrl = "https://pastebin.com/raw/MMruJhV9";
    final productsCsvUrl = "https://pastebin.com/raw/TzRVGAhP";

    try {
      final response = await http.get(Uri.parse(locationsCsvUrl));
      if (response.statusCode == 200) {
        final file = File(widget.layoutPath);
        await file.writeAsString(response.body);
        if (kDebugMode) {
          print('Downloaded and replaced');
        }
      }
    } catch (e) {
      print('Error downloading file: $e');
    }

    try {
      final response = await http.get(Uri.parse(productsCsvUrl));
      if (response.statusCode == 200) {
        final file = File(widget.productPath);
        await file.writeAsString(response.body);
        if (kDebugMode) {
          print('Downloaded and replaced');
        }
      }
    } catch (e) {
      print('Error downloading file: $e');
    }

  }

  Future<void> _scanBarcode() async {
    String barcodeScanResult = "";
    try {
      // barcodeScanResult = await barcode.FlutterBarcodeScanner.scanBarcode(
      //   "ff6666",
      //   "Cancel",
      //   true,
      //   barcode.ScanMode.BARCODE,
      // );
      if (kDebugMode) {
        print(barcodeScanResult);
      }
    } on PlatformException {
      barcodeScanResult = "";
    }

    if (!mounted) {
      return;
    }

    setState(() {
      scannedBarcodeResult = barcodeScanResult;
    });
  }

  void _handleBarcode(scanner.BarcodeCapture barcodes) {
    if (mounted) {
      setState(() {
        _barcode = barcodes.barcodes.firstOrNull;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget searchBar = SearchAnchor(
      builder: (BuildContext context, SearchController controller) {
        return IconButton(
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
        int floorNumber = 0;
        switch (floor) {
          case Floor.ground:
            floorNumber = 0;
          case Floor.first:
            floorNumber = 1;
          case Floor.second:
            floorNumber = 2;
        }
        _floors.animateTo(floorNumber);
        setState(() {
          wantedLocationId = _wantedLocationId;
        });
      },
    );

    if (!locationsLoaded) {
      _loadLayout().then((List<LayoutInfo> location) {
        setState(() {
          locationList = location;
          locationsLoaded = true;
        });
        if (kDebugMode) {
          print("Layout loaded");
          print(locationList);
        }
      });
    }

    if (!productsLoaded) {
      _loadProducts().then((List<ProductInfo> products) {
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

    List<LayoutInfo> groundFloorLayoutTable = locationList
      .where((LayoutInfo location) => location.floor == Floor.ground)
      .toList();
    List<LayoutInfo> firstFloorLayoutTable = locationList
      .where((LayoutInfo location) => location.floor == Floor.first)
      .toList();
    List<LayoutInfo> secondFloorLayoutTable = locationList
      .where((LayoutInfo location) => location.floor == Floor.second)
      .toList();

    return provider.Consumer<FileNotifier>(
      builder: (context, fileNotifier, child) {
        return Scaffold(
          appBar: AppBar(
            // TRY THIS: Try changing the color here to a specific color (to
            // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
            // change color while the other colors stay the same.
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            // Here we take the value from the MyHomePage object that was created by
            // the App.build method, and use it to set our appbar title.
            leading: IconButton(
              icon: Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  platform_widgets.platformPageRoute(
                    context: context,
                    builder: (context) => EditPage(),
                  ),
                );
              },
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.sync),
                onPressed: () async {
                  await _downloadAndReplace();
                  _loadLayout().then((List<LayoutInfo> locations) {
                    setState(() {
                      locationList = locations;
                    });
                  });
                  _loadProducts().then((List<ProductInfo> products) {
                    setState(() {
                      productList = products;
                    });
                  });
                  // TODO: impl
                },
              ),
              IconButton(
                icon: Icon(Icons.camera_alt_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => scanner.MobileScanner(
                        onDetect: _handleBarcode,
                      ),
                    ),
                  );
                  if (kDebugMode) {
                    print(_barcode);
                  }
                },
                // onPressed: () => _scanBarcode(), // async {
                  // if (Platform.isAndroid) {
                  //   int androidVersion = int.parse(Platform.version.split(".")[0]);
                  //   if (androidVersion < 10) {
                  //     // Request permissions differently for Android 9 and below
                  //     var status = await permission.Permission.camera.status;
                  //     if (!status.isGranted) {
                  //       await permission.Permission.camera.request();
                  //     }
                  //   }
                  // }
                  // permission.PermissionStatus status = await permission.Permission.camera.status;
                  // if (kDebugMode) {
                  //   print(status);
                  // }
                  // if (!status.isGranted) {
                  //   await permission.Permission.camera.request();
                  // }
                  // if (status.isGranted) {
                  //   await _scanBarcode();
                  // }
                // },
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
                locationList: groundFloorLayoutTable,
                productList: productList,
                productPath: widget.productPath,
                wantedLocationId: wantedLocationId,
                productCallback: _loadProducts,
              ),
              FloorLayout(
                key: ValueKey(wantedLocationId + 1),
                floor: Floor.first,
                locationList: firstFloorLayoutTable,
                productList: productList,
                productPath: widget.productPath,
                wantedLocationId: wantedLocationId,
                productCallback: _loadProducts,
              ),
              FloorLayout(
                key: ValueKey(wantedLocationId + 2),
                floor: Floor.second,
                locationList: secondFloorLayoutTable,
                productList: productList,
                productPath: widget.productPath,
                wantedLocationId: wantedLocationId,
                productCallback: _loadProducts,
              ),
            ],
          ) : Text("Loading ..."),
        );
      },
    );
  }
}

class FloorLayout extends StatefulWidget {
  final Floor floor;
  final List<LayoutInfo> locationList;
  final List<ProductInfo> productList;
  final String productPath;
  final int wantedLocationId;
  final Function productCallback;

  const FloorLayout({
    super.key,
    required this.floor,
    required this.locationList,
    required this.productList,
    required this.productPath,
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
                  TextButton(
                    child: const Text("Cancel"),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                  TextButton(
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
          List<ProductInfo> productListFiltered = widget.productList
            .where(
              (ProductInfo product) => product.locationId == racks[i].id,
            )
            .toList();

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RackProductList(
                locationId: racks[i].id,
                productList: productListFiltered,
                productPath: widget.productPath,
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
      .map((LayoutInfo layout) {
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
        double x0 = deviceWidth * layout.x0 / realWidth;
        double y0 = deviceHeight * layout.y0 / realHeight;
        double a = deviceWidth * layout.a / realWidth;
        double b = deviceHeight * layout.b / realHeight;

        return RackInfo(id: layout.id, floor: widget.floor, rack: Rect.fromLTWH(x0, y0, a, b));
      })
      .toList();

    return GestureDetector(
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      onTapCancel: onTapCancel,
      // onLongPressDown: onLongPressDown,
      child: CustomPaint(
        painter: RackPainter(racks: racks, wantedLocationId: widget.wantedLocationId),
        child: SizedBox.expand(), // Expands to fill the available space
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
  final List<ProductInfo> productList;
  final String productPath;
  final Function productCallback;

  const RackProductList({
    super.key,
    required this.locationId,
    required this.productList,
    required this.productPath,
    required this.productCallback
  });

  @override
  State<RackProductList> createState() => _RackProductListState();
}

class _RackProductListState extends State<RackProductList> {

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
            TextButton(
              onPressed: () {
                Navigator.pop(context, "");
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, textController.text),
              child: const Text("Submit"),
            )
          ],
        );
      },
    ) ?? "";
  }

  void _updateProductList(String path, String productId) {
    File productFile = File(path);
    productFile.writeAsStringSync("\n$productId;${widget.locationId}", mode: FileMode.append);
    // widget.productCallback();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Product List (ID: ${widget.locationId})"),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
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
              if (receivedProductId.isNotEmpty && receivedProductId.length == 10) {
                _updateProductList(widget.productPath, receivedProductId);
                var newContent = File(widget.productPath).readAsStringSync(encoding: utf8);
                provider.Provider.of<FileNotifier>(context, listen: false)
                  .updateContent(newContent);
              }
              // TODO: impl
            },
          )
        ],
      ),
      body: ListView.builder(
        itemCount: widget.productList.length,
        itemBuilder: (BuildContext context, int index) {
          String productId = widget.productList[index].productId;
          return ListTile(
            title: Text("${productId.substring(0, 7)} ${productId.substring(7, 10)}"),
            trailing: IconButton(
              icon: Icon(Icons.delete),
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

class EditPage extends StatefulWidget {
  const EditPage({super.key});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
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
        ],
      ),
    );
  }
}

class SecureApiKeyStorage {
  static const _storage = secure_storage.FlutterSecureStorage();
  static const _apiKey = "pastebin_api_key";

  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _apiKey, value: apiKey);
  }

  static Future<String> getApiKey() async {
    return await _storage.read(key: _apiKey) ?? "";
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
    String apiKey = await SecureApiKeyStorage.getApiKey();
    setState(() {
      _savedApiKey = apiKey;
      _controller.text = apiKey;
    });
  }

  Future<void> _saveApiKey() async {
    await SecureApiKeyStorage.saveApiKey(_controller.text);
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
            SizedBox(height: 20),
            platform_widgets.PlatformElevatedButton(
              onPressed: _saveApiKey,
              child: Text(
                "Save API Key",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              _savedApiKey.length != 0 ? "API Key Saved Securely" : "No API Key Saved",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
