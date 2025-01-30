import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Directory appCacheDir = await getApplicationCacheDirectory();
  appCacheDir.createSync(recursive: true);
  Directory configDir = Directory("${appCacheDir.path}/config");
  configDir.createSync(recursive: true);
  print("Cache directory found");
  print("config: ${configDir}");

  File layoutFile = File("${configDir.path}/layout.csv");
  if (!layoutFile.existsSync() || true) {
    print("Layout file created");
    layoutFile.createSync(recursive: true, exclusive: false); // TODO: Remember to change exclusive: true
    layoutFile.writeAsStringSync("id;floor;x0;y0;a;b\n0;0;0.5;0.7;5;5"); // TODO: Delete mock up data
  }

  File productFile = File("${configDir.path}/products.csv");
  if (!productFile.existsSync() || true) {
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
    List<List> transformedFields = fields.map((List product) {
      int productId = product[0];
      int layoutId = product[1];
      if (productId < 10) {
        return ["000000000${productId}", layoutId];
      } else if (productId < 100) {
        return ["00000000${productId}", layoutId];
      } else if (productId < 1_000) {
        return ["0000000${productId}", layoutId];
      } else if (productId < 10_000) {
        return ["000000${productId}", layoutId];
      } else if (productId < 100_000) {
        return ["00000${productId}", layoutId];
      } else if (productId < 1_000_000) {
        return ["0000${productId}", layoutId];
      } else if (productId < 10_000_000) {
        return ["000${productId}", layoutId];
      } else if (productId < 100_000_000) {
        return ["00${productId}", layoutId];
      } else if (productId < 1_000_000_000) {
        return ["0${productId}", layoutId];
      } else {
        return [productId.toString(), layoutId];
      }
    }).toList();
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
      ) : Text("Loading screen"),
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
  @override
  Widget build(BuildContext context) {
    // TODO: Rendering rectangles
    // TODO: Make rectangles clickable
    // TODO: Click should render list of products on bar/rail
    var x = widget.layoutTable[0].toString();
    return Text(x);
  }
}
