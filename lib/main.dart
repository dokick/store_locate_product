import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// Unit: meters
class StoreDimensions {
  // Notice that it says firstFloor and continuing, but the first floor corresponds to floor 0
  // english vs normal floor counting
  static const double firstFloorWidth = 20;
  static const double firstFloorHeight = 20;
  static const double secondFloorWidth = 20;
  static const double secondFloorHeight = 20;
  static const double thirdFloorWidth = 20;
  static const double thirdFloorHeight = 20;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Directory appCacheDir = await getApplicationCacheDirectory();
  appCacheDir.createSync(recursive: true);
  Directory configDir = Directory("${appCacheDir.path}/config");
  configDir.createSync(recursive: true);
  print("Cache directory found");
  print("config: ${configDir}");

  File layoutFile = File("${configDir.path}/layout.csv");
  if (!layoutFile.existsSync() || true) { // TODO: Remember to delete || true
    print("Layout file created");
    layoutFile.createSync(recursive: true, exclusive: false); // TODO: Remember to change exclusive: true
    layoutFile.writeAsStringSync("id;floor;x0;y0;a;b\n0;0;0.5;0.7;5;5"); // TODO: Delete mock up data
  }

  File productFile = File("${configDir.path}/products.csv");
  if (!productFile.existsSync() || true) { // TODO: Remember to delete || true
    print("Product file created");
    productFile.createSync(recursive: true, exclusive: false); // TODO: Remember to change exclusive: true
    productFile.writeAsStringSync("product_id;layout_id\n0000456001;0"); // TODO: Delete mock up data
  }

  runApp(MyApp(
    layoutPath: layoutFile.path,
    productPath: productFile.path,
  ));
}

class MyApp extends StatelessWidget {
  final String layoutPath;
  final String productPath;

  const MyApp({super.key, required this.layoutPath, required this.productPath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HM Wilma',
      theme: ThemeData(
        colorScheme: ColorScheme.dark(brightness: Brightness.dark),// ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(
        title: 'HM Wilma Locate Product',
        layoutPath: layoutPath,
        productPath: productPath,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  final String layoutPath;
  final String productPath;

  const MyHomePage({super.key, required this.title, required this.layoutPath, required this.productPath});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  late TabController _floors;
  bool layoutLoaded = false;
  bool productLoaded = false;
  List<List> layoutTable = [];
  List<List> productTable = [];

  @override
  void initState() {
    super.initState();
    _floors = TabController(length: 3, vsync: this);
  }

  // TODO: Consider switching to dartframe https://pub.dev/packages/dartframe

  Future<List<List>> _loadLayout() async {
    final stream = File(widget.layoutPath).openRead();
    final fields = await stream
        .transform(utf8.decoder)
        .transform(CsvToListConverter(fieldDelimiter: ";", eol: "\n"))
        .skip(1)
        .toList();
    print("Inside of loadLayout: ${fields}");
    print(fields[0][2]);
    print(fields[0][2].runtimeType);
    print(fields[0][3]);
    print(fields[0][3].runtimeType);
    // TODO: maybe do some filtering here, because of floors
    return fields;
  }

  Future<List<List>> _loadProducts() async {
    final stream = File(widget.productPath).openRead();
    final fields = await stream
        .transform(utf8.decoder)
        .transform(CsvToListConverter(fieldDelimiter: ";", eol: "\n"))
        .skip(1)
        .toList();
    print("Raw: $fields");
    print(fields[0][0].runtimeType);
    print(fields[0][1].runtimeType);
    List<List> transformedFields = fields
      .map((List product) {
        int productId = product[0];
        int layoutId = product[1];
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
        return ["${zeros}${productId}", layoutId];
    })
    .toList();
    return transformedFields;
  }

  @override
  Widget build(BuildContext context) {

    Widget searchBar = SearchAnchor(
      builder: (BuildContext context, SearchController controller) {
        return IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            controller.openView();
            // TODO: impl
          },
        );
      },
      suggestionsBuilder: (BuildContext context, SearchController controller) {
        return List.empty(growable: true);
      },
    );

    if (!layoutLoaded) {
      _loadLayout().then((List<List> layout) {
        layoutTable = layout;
        layoutLoaded = true;
        print("Layout loaded");
        print(layoutTable);
      });
    }

    if (!productLoaded) {
      _loadProducts().then((List<List> products) {
        productTable = products;
        productLoaded = true;
        print("Products loaded");
        print(productTable);
      });
    }

    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        leading: IconButton(
          onPressed: () {
            // TODO: impl
          },
          icon: Icon(Icons.add),
        ),
        actions: [
          IconButton(
            onPressed: () {
              // TODO: impl
            },
            icon: Icon(Icons.camera_alt_outlined),
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
      body: layoutLoaded ? TabBarView(
        controller: _floors,
        children: <Widget>[
          FloorLayout(
            floor: 0,
            layoutTable: layoutTable,
          ),
          FloorLayout(
            floor: 1,
            layoutTable: layoutTable,
          ),
          FloorLayout(
            floor: 2,
            layoutTable: layoutTable,
          ),
        ],
      ) : Text("Loading ..."),
    );
  }
}

class FloorLayout extends StatefulWidget {
  final int floor;
  final List<List> layoutTable;

  const FloorLayout({super.key, required this.floor, required this.layoutTable});

  @override
  State<FloorLayout> createState() => _FloorLayoutState();
}

class _FloorLayoutState extends State<FloorLayout> {
  List<Rect> racks = [];

  void onTapDown(TapDownDetails details) {
    Offset tapPosition = details.localPosition;

    for (int i = 0; i < racks.length; i++) {
      if (racks[i].contains(tapPosition)) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RackProductList(),
          ),
        );
        print("Rectangle $i clicked!");
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    racks = widget.layoutTable
      .map((List rack) {
        // All following values are given in meters.
        double x0 = rack[2].toDouble();
        double y0 = rack[3].toDouble();
        double a = rack[4].toDouble();
        double b = rack[5].toDouble();
        // Now follows the conversion
        double width = MediaQuery.sizeOf(context).width;
        double height = MediaQuery.sizeOf(context).height;
        x0 = width * x0 / StoreDimensions.firstFloorWidth;
        y0 = height * y0 / StoreDimensions.firstFloorHeight;
        a = width * a / StoreDimensions.firstFloorWidth;
        b = height * b / StoreDimensions.firstFloorHeight;
        return Rect.fromLTWH(x0, y0, a, b);
      })
      .toList();
    // TODO: Convert real life coordinates into pixels

    // TODO: Rendering rectangles
    // TODO: Make rectangles clickable
    // TODO: Click should render list of products on rack

    return GestureDetector(
      onTapDown: onTapDown,
      child: CustomPaint(
        painter: RackPainter(racks),
        child: SizedBox.expand(), // Expands to fill the available space
      ),
    );
  }
}

class RackPainter extends CustomPainter {
  final List<Rect> racks;

  RackPainter(this.racks);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()..color = Colors.grey.withValues(alpha: 0.5);

    for (var rect in racks) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class RackProductList extends StatefulWidget {
  const RackProductList({super.key});

  @override
  State<RackProductList> createState() => _RackProductListState();
}

class _RackProductListState extends State<RackProductList> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rectangle Details')),
      body: Center( // TODO: ListView Builder or similar for product list
        child: Text(
          'Details of Rectangle',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
