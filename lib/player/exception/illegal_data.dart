class IllegalDataException implements Exception {
  String source;
  String key;
  dynamic illegalValue;
  String expection;

  IllegalDataException({
    required this.source,
    required this.key,
    required this.illegalValue,
    required this.expection,
  });

  @override
  String toString() {
    return "Received illegal data from $source. The value to '$key' is $illegalValue, expecting $expection";
  }
}
