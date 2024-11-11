import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'result_page.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  PlatformFile? file;
  String baseUrl = "http://172.31.99.167:8000/";
  bool isTraining = false;
  bool isModelTrained = false;
  double? trainingTime;
  int? numSensors;
  List<List<dynamic>>? csvData;

  // Selected values
  String? selectedClassifier;
  String? selectedRegressor;

  // Available model options with descriptions
  final List<Map<String, String>> classifierOptions = [
    // {
    //   'value': 'logistic_regression',
    //   'label': 'Logistic Regression',
    //   'description': 'Best for linear classification problems'
    // },
    {
      'value': 'knn',
      'label': 'K-Nearest Neighbors',
      'description': 'Good for non-linear patterns with clean data'
    },
    {
      'value': 'naive_bayes',
      'label': 'Naive Bayes',
      'description': 'Efficient for high-dimensional data'
    },
    {
      'value': 'random_forest_classifier',
      'label': 'Random Forest Classifier',
      'description': 'Robust and handles non-linear patterns well'
    },
    {
      'value': 'xgboost_classifier',
      'label': 'XGBoost Classifier',
      'description': 'High performance with gradient boosting'
    },
    {
      'value': 'lda_classifier',
      'label': 'LDA Classifier',
      'description': 'Good for multi-class problems'
    },

    // ... other classifier options
  ];

  final List<Map<String, String>> regressorOptions = [
    {
      'value': 'linear_regression',
      'label': 'Linear Regression',
      'description': 'Best for linear relationships'
    },
    {
      'value': 'xgboost_regressor',
      'label': 'XGBoost Regressor',
      'description': 'High performance with gradient boosting'
    },
    {
      'value': 'decision_tree_regressor',
      'label': 'Decision Tree Regressor',
      'description': 'Good for non-linear patterns'
    },
    {
      'value': 'random_forest_regressor',
      'label': 'Random Forest Regressor',
      'description': 'Robust ensemble method'
    },

    // ... other regressor options
  ];

  @override
  void initState() {
    super.initState();
    selectedClassifier = classifierOptions.first['value'];
    selectedRegressor = regressorOptions.first['value'];
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          isModelTrained = data['models_trained'] ?? false;
          numSensors = data['num_sensors'] ?? 2; // Default to 2 sensors if not available
        });
      }
    } catch (e) {
      debugPrint('Error checking model status: $e');
    }
  }

  Future<void> _pickAndParseCsvFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          file = result.files.first;
        });

        // Check that the file has a valid path
        if (file?.path != null) {
          final input = File(file!.path!).openRead();
          final fields = await input
              .transform(utf8.decoder)
              .transform(const CsvToListConverter())
              .toList();

          // Validate CSV structure
          if (fields.isEmpty || fields[0].length < (numSensors ?? 2) + 3) {
            throw Exception('CSV file has an invalid structure');
          }

          setState(() {
            csvData = fields;  // Store the CSV data
          });
        } else {
          throw Exception('File path is null');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _handleTrainRequest() async {
    if (file == null || file?.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first')),
      );
      return;
    }

    setState(() => isTraining = true);

    try {
      final urlWithParams = Uri.parse(baseUrl).replace(
        path: 'train',
        queryParameters: {
          'classifier': selectedClassifier ?? 'random_forest_classifier',
          'regressor': selectedRegressor ?? 'random_forest_regressor',
        },
      );

      var request = http.MultipartRequest('POST', urlWithParams);
      var multipartFile = await http.MultipartFile.fromPath(
        'file',
        file!.path!,
        filename: file!.name,
        contentType: MediaType('text', 'csv'),
      );
      request.files.add(multipartFile);

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var result = json.decode(response.body);
        setState(() {
          isModelTrained = true;
          trainingTime = result['training_time'];
        });

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Training Complete'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Training completed in ${trainingTime?.toStringAsFixed(2)} seconds',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      const Text('What would you like to do next?'),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ResultPage(baseUrl: baseUrl),
                        ),
                      );
                    },
                    child: const Text('Make Predictions'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteFile();
                    },
                    child: const Text('Train New Models'),
                  ),
                ],
              );
            },
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Training failed: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during training: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isTraining = false);
      }
    }
  }

  // Update the _deleteFile method to also clear the csvData
  void _deleteFile() {
    setState(() {
      file = null;
      trainingTime = null;
      csvData = null;  // Add this line
    });
  }

  void _showModelInfo(String modelType, Map<String, String> model) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(model['label']!),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(model['description']!),
              const SizedBox(height: 16),
              Text('Type: $modelType'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gas Analysis - Training"),
        actions: [
          if (isModelTrained)
            IconButton(
              icon: const Icon(Icons.science),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ResultPage(baseUrl: baseUrl),
                  ),
                );
              },
              tooltip: 'Make Predictions',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isModelTrained)
                Card(
                  color: Colors.green[50],
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Models are trained and ready for predictions',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Model Selection Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Model Selection",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Classifier Dropdown
                      DropdownButtonFormField<String>(
                        value: selectedClassifier,
                        decoration: const InputDecoration(
                          labelText: 'Classifier',
                          border: OutlineInputBorder(),
                        ),
                        items: classifierOptions.map((option) {
                          return DropdownMenuItem<String>(
                            value: option['value'],
                            child: Text(option['label']!),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedClassifier = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // Regressor Dropdown
                      DropdownButtonFormField<String>(
                        value: selectedRegressor,
                        decoration: const InputDecoration(
                          labelText: 'Regressor',
                          border: OutlineInputBorder(),
                        ),
                        items: regressorOptions.map((option) {
                          return DropdownMenuItem<String>(
                            value: option['value'],
                            child: Text(option['label']!),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedRegressor = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _handleTrainRequest,
                        child: isTraining
                            ? const CircularProgressIndicator(
                          color: Colors.white,
                        )
                            : const Text("Train Model"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // File Upload Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Upload CSV Data",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.file_upload),
                        label: const Text("Select CSV File"),
                        onPressed: _pickAndParseCsvFile,
                      ),
                      if (file != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text("Selected file: ${file!.name}"),
                        ),
                    ],
                  ),
                ),
              ),

              // Add the data preview section
              if (csvData != null) ...[
                const SizedBox(height: 16),
                _buildDataPreview(),
              ],
            ],
          ),
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
                  "Data Preview",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${csvData!.length - 1} rows total',
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
                columns: csvData!.first.map<DataColumn>((header) {
                  return DataColumn(
                    label: Text(
                      header.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
                rows: csvData!.skip(1).take(5).map<DataRow>((row) {
                  return DataRow(
                    cells: row.map<DataCell>((cell) {
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
}