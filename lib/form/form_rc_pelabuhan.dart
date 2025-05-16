import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/pelabuhan_service.dart';

class FormPelabuhanScreen extends StatefulWidget {
  final dynamic order;
  const FormPelabuhanScreen({super.key, required this.order});

  @override
  _FormPelabuhanScreenState createState() => _FormPelabuhanScreenState();
}

class _FormPelabuhanScreenState extends State<FormPelabuhanScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _containerController = TextEditingController();
  final TextEditingController _sealController = TextEditingController();
  final TextEditingController _seal2Controller = TextEditingController();
  final String _ordersUrl =
      'http://192.168.20.65/ralisa_api/index.php/api/get_new_salesorder_for_krani_pelabuhan';
  // final String _ordersUrl =
  //     'https://api3.ralisa.co.id/index.php/api/get_new_salesorder_for_krani_pelabuhan';
  final String _sealUrl =
      'http://192.168.20.65/ralisa_api/index.php/api/get_seal_number';
  // final String _sealUrl =
  //     'https://api3.ralisa.co.id/index.php/api/get_seal_number';
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  String? _namaPetugas;
  Map<String, dynamic> _databaseData = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  late PelabuhanService _pelabuhanService;
  List<String> _sealSuggestions = [];
  bool _isLoadingSuggestions = false;
  Timer? _sealSearchDebounce;
  int _activeSealField = 0; // 0 = none, 1 = seal1, 2 = seal2
  static const double _maxSuggestionHeight = 250;
  final FocusNode _sealFocusNode1 = FocusNode();

  @override
  void initState() {
    super.initState();
    _pelabuhanService = PelabuhanService();
    _initializeData();
    _sealFocusNode1.addListener(() {
      if (!_sealFocusNode1.hasFocus) {
        _validateSealInput(_sealController.text.trim());
      }
    });
  }

  @override
  void dispose() {
    _sealSearchDebounce?.cancel();
    _containerController.dispose();
    _sealController.dispose();
    _seal2Controller.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _loadPetugas(),
      _checkIfAlreadySubmitted(),
      _loadDraftIfAny(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _loadPetugas() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _namaPetugas = prefs.getString('username') ?? 'Tidak diketahui';
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        if (await file.exists()) {
          if (mounted) {
            setState(() {
              _selectedImage = file;
            });
          }
          await _autoSaveDraft();
          if (mounted) {
            showDialog(
              context: context,
              builder:
                  (context) => AlertDialog(
                    content: const Text('Pastikan data telah sesuai'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('Iya'),
                      ),
                    ],
                  ),
            );
          }
        } else {
          throw Exception('File tidak ditemukan');
        }
      } else {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal memilih gambar: $e')));
      }
    }
  }

  Future<void> _checkIfAlreadySubmitted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final res = await http.get(Uri.parse('$_ordersUrl?token=$token'));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final archiveList = data['data'] ?? [];

        final isSubmitted = archiveList.any(
          (item) =>
              item['so_id'].toString() == widget.order['so_id'].toString() &&
              item['foto_rc'] != null &&
              item['foto_rc'].toString().isNotEmpty,
        );

        if (isSubmitted && mounted) {
          final prefs = await SharedPreferences.getInstance();
          final drafts = prefs.getStringList('rc_drafts') ?? [];
          final updated =
              drafts
                  .where((e) => jsonDecode(e)['so_id'] != widget.order['so_id'])
                  .toList();
          await prefs.setStringList('rc_drafts', updated);

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Data ini telah disubmit.')));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      print('Error checking submission status: $e');
    }
  }

  Future<void> _loadDraftIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = prefs.getStringList('rc_drafts') ?? [];
    final existing = drafts.firstWhere(
      (e) => jsonDecode(e)['so_id'] == widget.order['so_id'],
      orElse: () => '',
    );

    if (existing.isNotEmpty) {
      final data = jsonDecode(existing);
      _containerController.text = data['driver_container_num'] ?? '';
      _sealController.text = data['driver_seal_num1'] ?? '';
      _seal2Controller.text = data['driver_seal_num2'] ?? '';
      String fotoPath = data['foto_rc'] ?? '';
      if (fotoPath.isNotEmpty) {
        _selectedImage = File(fotoPath);
      }

      setState(() {
        _databaseData = data;
      });
    } else {
      _containerController.text = widget.order['driver_container_num'] ?? '';
      _sealController.text = widget.order['driver_seal_num1'] ?? '';
      _seal2Controller.text = widget.order['driver_seal_num2'] ?? '';

      setState(() {
        _databaseData = widget.order;
      });
    }
  }

  Future<void> _autoSaveDraft() async {
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = prefs.getStringList('rc_drafts') ?? [];

      final draft = {
        "so_id": widget.order['so_id'],
        "no_ro": widget.order['no_ro'] ?? '',
        "destination_name": widget.order['destination_name'] ?? '',
        "driver_name": widget.order['driver_name'] ?? '',
        "truck_name": widget.order['truck_name'] ?? '',
        "sender_name": widget.order['sender_name'] ?? '',
        "nama_kapal": widget.order['nama_kapal'] ?? '',
        "nomor_voy": widget.order['nomor_voy'] ?? '',
        "nama_pelayaran": widget.order['nama_pelayaran'] ?? '',
        "driver_container_num": _containerController.text.trim(),
        "driver_seal_num1": _sealController.text.trim(),
        "driver_seal_num2": _seal2Controller.text.trim(),
        "foto_rc": _selectedImage?.path ?? "",
        "username": _namaPetugas ?? "Tidak diketahui",
      };

      final updatedDrafts =
          drafts.where((e) {
            try {
              return jsonDecode(e)['so_id'] != widget.order['so_id'];
            } catch (_) {
              return false;
            }
          }).toList();

      updatedDrafts.add(jsonEncode(draft));
      await prefs.setStringList('rc_drafts', updatedDrafts);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal menyimpan draft: $e')));
      }
      print('Error auto-saving draft: $e');
    }
  }

  Future<void> _fetchSealSuggestions(String query, int fieldType) async {
    if (query.isEmpty) {
      setState(() {
        _sealSuggestions = [];
        _activeSealField = 0;
      });
      return;
    }

    if (_sealSearchDebounce?.isActive ?? false) _sealSearchDebounce?.cancel();

    setState(() => _activeSealField = fieldType);

    _sealSearchDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        setState(() => _isLoadingSuggestions = true);

        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token') ?? '';

        final response = await http.get(
          Uri.parse('$_sealUrl?token=$token&seal_number=$query'),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == true) {
            final seals =
                (data['data'] as List)
                    .map((item) => item['number'].toString())
                    .where((number) => number.isNotEmpty)
                    .toList();

            setState(() => _sealSuggestions = seals);
          }
        }
      } catch (e) {
        print('Error fetching seal suggestions: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoadingSuggestions = false);
        }
      }
    });
  }

  Future<void> _validateSealInput(String input) async {
    if (input.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final response = await http.get(
        Uri.parse('$_sealUrl?token=$token&seal_number=$input'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final seals =
            (data['data'] as List)
                .map((item) => item['number'].toString())
                .where((number) => number.isNotEmpty)
                .toList();

        if (!seals.contains(input)) {
          _showInvalidInputDialog(
            'Nomor Segel 1 tidak sesuai dengan data tersedia.',
          );

          // Kosongkan input setelah pop-up
          setState(() {
            _sealController.clear();
          });
        }
      }
    } catch (e) {
      print('Error during seal validation: $e');
    }
  }

  void _showInvalidInputDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Peringatan'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _submitData() async {
    // Lock untuk mencegah multiple submissions
    if (_isSubmitting) return;

    if (!_isAllFieldsFilled() || _selectedImage == null) {
      String errorMessage = '';
      if (_containerController.text.trim().isEmpty)
        errorMessage = 'Nomor Kontainer';
      else if (_sealController.text.trim().isEmpty)
        errorMessage = 'Nomor Segel 1';
      else if (_selectedImage == null)
        errorMessage = 'Foto RC';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mohon isi $errorMessage terlebih dahulu')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Cek ulang seal 1 dan 2 via API
      bool seal1Valid = await _isSealValid(_sealController.text.trim());

      if (!seal1Valid) {
        if (mounted) {
          _showInvalidInputDialog('Nomor Segel 1 tidak valid saat submit.');
          setState(() => _sealController.clear());
        }
        return;
      }

      // Cek ulang status data sebelum submit
      final isAlreadySubmitted = await _checkSubmissionStatus();
      if (isAlreadySubmitted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data ini sudah disubmit sebelumnya')),
          );
          Navigator.pop(context, true);
        }
        return;
      }

      bool success = await _pelabuhanService.submitRC(
        soId: widget.order['so_id'].toString(),
        containerNum: _containerController.text.trim(),
        sealNumber: _sealController.text.trim(),
        sealNumber2: _seal2Controller.text.trim(),
        fotoRcPath: _selectedImage!.path,
        agent: _namaPetugas ?? "Tidak diketahui",
      );

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        final drafts = prefs.getStringList('rc_drafts') ?? [];
        final updated =
            drafts
                .where((e) => jsonDecode(e)['so_id'] != widget.order['so_id'])
                .toList();
        await prefs.setStringList('rc_drafts', updated);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data berhasil dikirim')),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Gagal mengirim data')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terjadi kesalahan: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  // Fungsi baru untuk cek status submission
  Future<bool> _checkSubmissionStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final res = await http.get(Uri.parse('$_ordersUrl?token=$token'));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final archiveList = data['data'] ?? [];

        return archiveList.any(
          (item) =>
              item['so_id'].toString() == widget.order['so_id'].toString() &&
              item['foto_rc'] != null &&
              item['foto_rc'].toString().isNotEmpty,
        );
      }
      return false;
    } catch (e) {
      print('Error checking submission status: $e');
      return false;
    }
  }

  bool _isAllFieldsFilled() {
    return _containerController.text.trim().isNotEmpty &&
        _sealController.text.trim().isNotEmpty;
  }

  Future<bool> _isSealValid(String seal) async {
    if (seal.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final response = await http.get(
        Uri.parse('$_sealUrl?token=$token&seal_number=$seal'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final seals =
            (data['data'] as List)
                .map((item) => item['number'].toString())
                .where((number) => number.isNotEmpty)
                .toList();
        return seals.contains(seal);
      }
    } catch (e) {
      print('Error validating seal during submit: $e');
    }

    return false;
  }

  Widget _buildStyledInfoWrap() {
    final items = [
      {
        'label': 'Nomor RO',
        'value': _databaseData['no_ro'] ?? widget.order['no_ro'] ?? '-',
      },
      {
        'label': 'Tujuan',
        'value':
            _databaseData['destination_name'] ??
            widget.order['destination_name'] ??
            '-',
      },
      {
        'label': 'Supir',
        'value':
            _databaseData['driver_name'] ?? widget.order['driver_name'] ?? '-',
      },
      {
        'label': 'Nomor Mobil',
        'value':
            _databaseData['truck_name'] ?? widget.order['truck_name'] ?? '-',
      },
      {
        'label': 'Pabrik',
        'value':
            _databaseData['sender_name'] ?? widget.order['sender_name'] ?? '-',
      },
      {
        'label': 'Kapal',
        'value':
            _databaseData['nama_kapal'] ?? widget.order['nama_kapal'] ?? '-',
      },
      {
        'label': 'Voyage',
        'value': _databaseData['nomor_voy'] ?? widget.order['nomor_voy'] ?? '-',
      },
      {
        'label': 'Pelayaran',
        'value':
            _databaseData['nama_pelayaran'] ??
            widget.order['nama_pelayaran'] ??
            '-',
      },
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children:
          items.map((item) {
            return IntrinsicWidth(
              child: IntrinsicHeight(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, 236, 212, 212),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item['label']!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['value']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Memuat data...'),
        ],
      ),
    );
  }

  Widget _buildSuggestionDropdown({required TextEditingController controller}) {
    return Container(
      margin: EdgeInsets.only(top: 4),
      constraints: BoxConstraints(
        maxHeight: _maxSuggestionHeight, // Batasi tinggi maksimal
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Scrollbar(
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _sealSuggestions.length,
          itemBuilder: (context, index) {
            return ListTile(
              dense: true, // Buat item lebih compact
              visualDensity: VisualDensity.compact, // Padatkan tampilan
              contentPadding: EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                _sealSuggestions[index],
                style: TextStyle(fontSize: 14),
              ),
              onTap: () {
                setState(() {
                  controller.text = _sealSuggestions[index];
                  _sealSuggestions = [];
                  _activeSealField = 0;
                });
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        setState(() {
          _sealSuggestions = [];
          _activeSealField = 0;
        });
        await _autoSaveDraft();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data disimpan sebagai draft')),
        );
        Navigator.pop(context, true);
        return true;
      },
      child: GestureDetector(
        onTap: () {
          setState(() {
            _sealSuggestions = [];
            _activeSealField = 0;
          });
          FocusScope.of(context).unfocus();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Form Pelabuhan'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                await _autoSaveDraft();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Data disimpan sebagai draft'),
                    ),
                  );
                  Navigator.pop(context, true);
                }
              },
            ),
          ),
          body:
              _isLoading
                  ? _buildLoadingIndicator()
                  : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        children: [
                          _buildStyledInfoWrap(),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _containerController,
                            decoration: const InputDecoration(
                              labelText: 'Nomor Kontainer',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            onChanged: (_) => _autoSaveDraft(),
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                focusNode: _sealFocusNode1,
                                controller: _sealController,
                                decoration: InputDecoration(
                                  labelText: 'Nomor Segel 1',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  suffixIcon:
                                      (_isLoadingSuggestions &&
                                              _activeSealField == 1)
                                          ? Padding(
                                            padding: EdgeInsets.all(8),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : null,
                                ),
                                onTap:
                                    () => setState(() => _activeSealField = 1),
                                onChanged: (value) {
                                  _autoSaveDraft();
                                  _fetchSealSuggestions(value, 1);
                                },
                              ),
                              if (_sealSuggestions.isNotEmpty &&
                                  _activeSealField == 1)
                                _buildSuggestionDropdown(
                                  controller: _sealController,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _seal2Controller,
                                decoration: InputDecoration(
                                  labelText: 'Nomor Segel 2',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                onChanged: (_) => _autoSaveDraft(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text("Pilih Sumber Gambar"),
                                    actions: [
                                      TextButton.icon(
                                        icon: const Icon(Icons.camera_alt),
                                        label: const Text("Kamera"),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _pickImage(ImageSource.camera);
                                        },
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.image),
                                        label: const Text("Galeri"),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _pickImage(ImageSource.gallery);
                                        },
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Pilih Foto RC'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_selectedImage != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder:
                                          (_) => Dialog(
                                            insetPadding: const EdgeInsets.all(
                                              16,
                                            ),
                                            backgroundColor: Colors.transparent,
                                            child: Stack(
                                              children: [
                                                InteractiveViewer(
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.file(
                                                      _selectedImage!,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 10,
                                                  right: 10,
                                                  child: ElevatedButton(
                                                    onPressed:
                                                        () =>
                                                            Navigator.of(
                                                              context,
                                                            ).pop(),
                                                    style: ElevatedButton.styleFrom(
                                                      shape:
                                                          const CircleBorder(),
                                                      backgroundColor:
                                                          Colors.red,
                                                      padding:
                                                          const EdgeInsets.all(
                                                            10,
                                                          ),
                                                      minimumSize: const Size(
                                                        40,
                                                        40,
                                                      ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.close,
                                                      color: Colors.white,
                                                      size: 24,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      _selectedImage!,
                                      height: 150,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() => _selectedImage = null);
                                      _autoSaveDraft();
                                    },
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Hapus Foto',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            const Center(child: Text('Belum ada foto dipilih')),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed:
                                  _isSubmitting
                                      ? null
                                      : () {
                                        showDialog(
                                          context: context,
                                          builder:
                                              (context) => AlertDialog(
                                                content: const Text(
                                                  'Yakin data telah sesuai?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed:
                                                        () => Navigator.pop(
                                                          context,
                                                        ),
                                                    child: const Text('Tidak'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      _submitData();
                                                    },
                                                    child: const Text(
                                                      'Iya, Kirim',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                        );
                                      },
                              icon:
                                  _isSubmitting
                                      ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : const Icon(
                                        Icons.send,
                                        color: Colors.white,
                                      ),
                              label: Text(
                                _isSubmitting ? 'Mengirim...' : 'Kirim Data',
                                style: const TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF4C4C),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
                                ),
                                textStyle: const TextStyle(fontSize: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
        ),
      ),
    );
  }
}
