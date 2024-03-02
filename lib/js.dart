@JS()
library callable_function;

import 'package:js/js.dart';

@JS('getChildren')
external set getChildren(void Function(String id) f);

@JS('hljs.highlightAll')
external void highlightAll();
