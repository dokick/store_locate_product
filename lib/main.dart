// x0 and a are orthogonal to the entrance and y0 and b are parallel

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// Unit: meters
class StoreDimensions {
  // Notice that it says firstFloor and continuing, but the first floor corresponds to floor 0
  // american vs german floor counting
  static const double groundFloorWidth = 20;  // m
  static const double groundFloorHeight = 20;  // m
  static const double firstFloorWidth = 20;  // m
  static const double firstFloorHeight = 20;  // m
  static const double secondFloorWidth = 20;  // m
  static const double secondFloorHeight = 20;  // m
}

@immutable
class RackInfo {
  final int id;
  final int floor;
  final Rect rack;

  const RackInfo({required this.id, required this.floor, required this.rack});
}

@immutable
class ProductInfo {
  final String productId;
  final int layoutId;

  const ProductInfo({required this.productId, required this.layoutId});
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
  if (!layoutFile.existsSync() || true) {  // TODO: Remember to delete || true
    print("Layout file created");
    layoutFile.createSync(recursive: true, exclusive: false);  // TODO: Remember to change exclusive: true
    layoutFile.writeAsStringSync("id;floor;x0;y0;a;b\n0;0;0.5;0.7;5;5\n1;1;0;0;7;3\n2;2;1;1;4;2\n3;0;6;6;1;1");  // TODO: Delete mock up data
  }

  File productFile = File("${configDir.path}/products.csv");
  if (!productFile.existsSync() || true) {  // TODO: Remember to delete || true
    print("Product file created");
    productFile.createSync(recursive: true, exclusive: false);  // TODO: Remember to change exclusive: true
    productFile.writeAsStringSync("product_id;layout_id\n0000456001;0\n1234567002;1\n7654321003;2");  // TODO: Delete mock up data
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
  int wantedLayoutId = -1;

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
        return ["$zeros$productId", layoutId];
    })
    .toList();
    return transformedFields;
  }

  (int, int) _locateProduct(String productId) {
    for (List product in productTable) {
      if (product[0] == productId) {
        int layoutId = product[1];
        for (List layout in layoutTable) {
          if (layout[0] == layoutId) {
            return (product[1], layout[1]);
          }
        }
        break;
      }
    }
    return (-1, -1);
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
        var (_wantedLayoutId, floor) = _locateProduct(productId);
        _floors.animateTo(floor);
        setState(() {
          wantedLayoutId = _wantedLayoutId;
        });
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

    List<List> groundFloorLayoutTable = layoutTable.where((List layout) => layout[1] == 0).toList();
    List<List> firstFloorLayoutTable = layoutTable.where((List layout) => layout[1] == 1).toList();
    List<List> secondFloorLayoutTable = layoutTable.where((List layout) => layout[1] == 2).toList();

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
            key: ValueKey(wantedLayoutId + 0),
            floor: 0,
            layoutTable: groundFloorLayoutTable,
            productList: productTable,
            wantedLayoutId: wantedLayoutId,
          ),
          FloorLayout(
            key: ValueKey(wantedLayoutId + 1),
            floor: 1,
            layoutTable: firstFloorLayoutTable,
            productList: productTable,
            wantedLayoutId: wantedLayoutId,
          ),
          FloorLayout(
            key: ValueKey(wantedLayoutId + 2),
            floor: 2,
            layoutTable: secondFloorLayoutTable,
            productList: productTable,
            wantedLayoutId: wantedLayoutId,
          ),
        ],
      ) : Text("Loading ..."),
    );
  }
}

class FloorLayout extends StatefulWidget {
  final int floor;
  final List<List> layoutTable;
  final List<List> productList;
  final int wantedLayoutId;

  const FloorLayout({
    super.key,
    required this.floor,
    required this.layoutTable,
    required this.productList,
    required this.wantedLayoutId,
  });

  @override
  State<FloorLayout> createState() => _FloorLayoutState();
}

class _FloorLayoutState extends State<FloorLayout> {
  List<RackInfo> racks = [];

  void onTapDown(TapDownDetails details) {
    Offset tapPosition = details.localPosition;

    for (int i = 0; i < racks.length; i++) {
      if (racks[i].rack.contains(tapPosition)) {
        List<ProductInfo> productListFiltered = widget.productList
          .where(
            (List product) => product[1] == racks[i].id,
          )
          .map(
            (List product) => ProductInfo(productId: product[0], layoutId: product[1]),
          )
          .toList();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RackProductList(productList: productListFiltered),
          ),
        );
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
        // Converting into device specific measurements
        double width = MediaQuery.sizeOf(context).width;
        double height = MediaQuery.sizeOf(context).height;

        double realWidth = 1.0;
        double realHeight = 1.0;
        switch (widget.floor) {
          case 0: {
            realWidth = StoreDimensions.groundFloorWidth;
            realHeight = StoreDimensions.groundFloorHeight;
          }
          case 1: {
            realWidth = StoreDimensions.firstFloorWidth;
            realHeight = StoreDimensions.firstFloorHeight;
          }
          case 2: {
            realWidth = StoreDimensions.secondFloorWidth;
            realHeight = StoreDimensions.secondFloorHeight;
          }
          default: {  // TODO: What to do when floor isn't 0, 1 or 2
            realWidth = StoreDimensions.groundFloorWidth;
            realHeight = StoreDimensions.groundFloorHeight;
          }
        }
        x0 = width * x0 / realWidth;
        y0 = height * y0 / realHeight;
        a = width * a / realWidth;
        b = height * b / realHeight;
        return RackInfo(id: rack[0], floor: rack[1], rack: Rect.fromLTWH(x0, y0, a, b));
      })
      .toList();

    return GestureDetector(
      onTapDown: onTapDown,
      child: CustomPaint(
        painter: RackPainter(racks: racks, wantedLayoutId: widget.wantedLayoutId),
        child: SizedBox.expand(), // Expands to fill the available space
      ),
    );
  }
}

class RackPainter extends CustomPainter {
  final List<RackInfo> racks;
  final int wantedLayoutId;

  RackPainter({required this.racks, required this.wantedLayoutId});

  @override
  void paint(Canvas canvas, Size size) {
    Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5; // TODO: Adjust strokeWidth if necessary

    for (var RackInfo(:id, :rack) in racks) {
      Color color = (id == wantedLayoutId) ? Colors.red : Colors.grey;
      Paint fillPaint = Paint()
        ..color = color.withValues(alpha: 0.5);

      canvas.drawRect(rack, fillPaint);
      if (id == wantedLayoutId) {
        canvas.drawRect(rack, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class RackProductList extends StatefulWidget {
  final List<ProductInfo> productList;

  const RackProductList({super.key, required this.productList});

  @override
  State<RackProductList> createState() => _RackProductListState();
}

class _RackProductListState extends State<RackProductList> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Product List"),
        actions: [
          IconButton(
            onPressed: () {
              // TODO: impl
            },
            icon: Icon(Icons.add),
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
              onPressed: () {
                // TODO: impl
              },
              icon: Icon(Icons.delete),
            ),
          );
        }
      ),
    );
  }
}
