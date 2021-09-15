import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:realtime_storage_flutter/services/realtime_storage.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final storage = RealtimeStorage(
    baseURL: 'http://192.168.100.3:8888',
    database: 'db1',
  );

  late Collection productsCollection;
  @override
  void initState() {
    super.initState();
    productsCollection = storage.collection('products');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Storage'),
      ),
      body: StreamBuilder<List<DocumentSnapshot>>(
        stream: productsCollection.stream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final list = snapshot.data ?? [];
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final doc = list.elementAt(index);
              return ListTile(
                title: Text(doc['nama'] ?? 'Deleted'),
                subtitle: Text(doc['price'].toString()),
                trailing: IconButton(
                  onPressed: () async {
                    await doc.delete();
                  },
                  icon: const Icon(CupertinoIcons.delete),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addItem() async {
    await productsCollection.add(
      {
        'nama': 'Item ${DateTime.now().millisecondsSinceEpoch}',
        'price': 5000,
      },
    );
  }
}
