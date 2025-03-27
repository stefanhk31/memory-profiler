import 'dart:math';

import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memory Profiling Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _allocations = <List<DateTime>>[];

  @override
  initState() {
    super.initState();
  }

  void _increaseAllocations() {
    setState(() {
      final alloc = Random().nextInt(1000000);
      _allocations.add(List.generate(alloc, (_) => DateTime.now()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Total allocations: ${_allocations.isEmpty ? 0 : _allocations.map((a) => a.length).reduce((a, b) => a + b)}',
            ),
            Flexible(
              child: ListView.builder(
                itemCount: _allocations.length,
                itemBuilder: (context, index) {
                  final allocation = _allocations[index];
                  allocation.length;
                  return ListTile(
                    title: Text('Allocation #${index + 1}'),
                    subtitle: Text('Items: ${allocation.length}'),
                  );
                },
              ),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _increaseAllocations,
        tooltip: 'Add More Allocations',
        child: const Icon(Icons.add),
      ),
    );
  }
}
