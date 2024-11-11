  import 'dart:convert';
  import 'dart:typed_data';
  import 'package:flutter/material.dart';
  import 'package:file_picker/file_picker.dart';
  import 'package:http/http.dart' as http;
  import 'package:http_parser/http_parser.dart';
  import 'package:csv/csv.dart';
  
  class ResultPage extends StatefulWidget {
    final String baseUrl;
  
    const ResultPage({
      super.key,
      required this.baseUrl,
    });
  
    @override
    State<ResultPage> createState() => _ResultPageState();
  }
  
  class _ResultPageState extends State<ResultPage> {
    PlatformFile? file;
    bool isPredicting = false;
    List<List<dynamic>>? csvData;
    Map<String, dynamic>? predictionResult;
    String? error;
  
    Future<void> _pickAndParseCsvFile() async {
      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
          allowMultiple: false,
          withData: true,
        );
  
        if (result != null && result.files.isNotEmpty) {
          final pickedFile = result.files.first;
          if (pickedFile.bytes == null) {
            throw Exception('Could not read file bytes');
          }
  
          setState(() {
            file = pickedFile;
            error = null;
          });
  
          final csvString = utf8.decode(pickedFile.bytes!);
          final fields = const CsvToListConverter().convert(csvString);
          await _validateAndProcessCsv(fields);
        }
      } catch (e) {
        setState(() {
          error = 'Error reading file: $e';
        });
        _showErrorSnackbar('Error reading file: $e');
      }
    }
  
    Future<void> _validateAndProcessCsv(List<List<dynamic>> fields) async {
      if (fields.isEmpty) {
        throw Exception('CSV file is empty');
      }
  
      // Convert all values to non-null strings
      List<List<dynamic>> sanitizedFields = fields.map((row) {
        return row.map((cell) {
          if (cell == null) {
            return '';  // Convert null to empty string
          }
          // Convert numbers to fixed decimal places
          if (cell is num) {
            return cell.toStringAsFixed(6);
          }
          return cell.toString();  // Convert everything else to string
        }).toList();
      }).toList();
  
      final headers = sanitizedFields[0].map((e) => e.toString()).toList();
      final requiredColumns = ['Time'] + headers.where((col) => col.startsWith('Sensor')).toList();
  
      if (!requiredColumns.every((col) => headers.contains(col))) {
        throw Exception('CSV must contain columns: ${requiredColumns.join(", ")}');
      }
  
      setState(() {
        csvData = sanitizedFields;
        error = null;
      });
  
      await _handlePrediction();
    }
  
    void _showErrorSnackbar(String message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {},
              textColor: Colors.white,
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  
    void _showSuccessSnackbar(String message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  
    Future<void> _handlePrediction() async {
      if (file == null || file!.bytes == null) {
        _showErrorSnackbar('Please select a valid file first');
        return;
      }
  
      setState(() {
        isPredicting = true;
        error = null;
      });
  
      try {
        final url = Uri.parse('${widget.baseUrl}predict');
        var request = http.MultipartRequest('POST', url);
  
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file!.bytes!,
            filename: file!.name,
            contentType: MediaType('text', 'csv'),
          ),
        );
  
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
  
        if (response.statusCode == 200) {
          final result = json.decode(response.body);
          setState(() {
            predictionResult = result;
          });
          _showSuccessSnackbar('Predictions completed successfully');
        } else {
          throw Exception('Prediction failed: ${response.body}');
        }
      } catch (e) {
        setState(() {
          error = e.toString();
        });
        _showErrorSnackbar('Error during prediction: $e');
      } finally {
        setState(() => isPredicting = false);
      }
    }
  
    Widget _buildFileUploadSection() {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Make Predictions",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Upload a CSV file with columns: Time, Sensor 1, Sensor 2, ...",
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              if (file == null)
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _pickAndParseCsvFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text("Select Test File"),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade900.withOpacity(0.2)
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue.shade700
                          : Colors.blue.shade200!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.file_present,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file!.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${(file!.size / 1024).toStringAsFixed(2)} KB',
                              style: TextStyle(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isPredicting)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      else
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _handlePrediction,
                              tooltip: 'Retry Prediction',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  file = null;
                                  csvData = null;
                                  predictionResult = null;
                                  error = null;
                                });
                              },
                              tooltip: 'Remove File',
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  
    Widget _buildPredictionsTable() {
      if (predictionResult == null || predictionResult!.isEmpty) {
        return const SizedBox(height: 25, child: Text("No predictions available"));
      }
  
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Prediction Results",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  headingRowColor: MaterialStateProperty.all(
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.grey[50],
                  ),
                  columns: const [
                    DataColumn(
                      label: Text(
                        'Predicted Gas Type',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Predicted Concentration',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  rows: [
                    DataRow(
                      cells: [
                        DataCell(
                          Text(
                            predictionResult!['predicted_gas_type'].toString(),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DataCell(
                          Text(
                            predictionResult!['predicted_concentration'].toString(),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  
    Widget _buildDataPreview() {
      if (csvData == null || csvData!.isEmpty) {
        return const SizedBox.shrink();
      }
  
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Input Data Preview",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${csvData!.length - 1} rows',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  headingRowColor: MaterialStateProperty.all(
                    Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.grey[50],
                  ),
                  columns: csvData!.first.map<DataColumn>((col) {
                    return DataColumn(
                      label: Text(
                        col.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  rows: csvData!.skip(1).take(5).map<DataRow>((row) {
                    return DataRow(
                      cells: row.map<DataCell>((cell) {
                        // Try to convert string to double for formatting if possible
                        String displayValue = cell.toString();
                        try {
                          final value = double.parse(cell.toString());
                          displayValue = value.toStringAsFixed(6);
                        } catch (_) {
                          // Keep original string if not a number
                        }
                        return DataCell(
                          Text(
                            displayValue,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
              if (csvData!.length > 6)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Showing first 5 rows of ${csvData!.length - 1}',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  
    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Gas Analysis - Predictions"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFileUploadSection(),
              if (csvData != null && csvData!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildDataPreview(),
              ],
              if (predictionResult != null) ...[
                const SizedBox(height: 16),
                _buildPredictionsTable(),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    }
  }