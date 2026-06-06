import 'dart:io';

/// Logical processor count from the host OS.
int get processorCoreCount => Platform.numberOfProcessors;
