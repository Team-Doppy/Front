import 'package:flutter/material.dart';
import 'package:doppy/theme/app_colors.dart';

/// 위치 선택 다이얼로그
/// 실제로는 Google Maps나 다른 지도 서비스를 사용할 수 있습니다
class LocationPickerDialog extends StatefulWidget {
  final Function(double lat, double lng, String title, String address)
  onLocationSelected;

  const LocationPickerDialog({super.key, required this.onLocationSelected});

  @override
  State<LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<LocationPickerDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  // 미리 정의된 위치들 (실제로는 지도에서 선택)
  final List<Map<String, dynamic>> _predefinedLocations = [
    {
      'title': '서울시청',
      'address': '서울특별시 중구 세종대로 110',
      'lat': 37.5665,
      'lng': 126.9780,
    },
    {
      'title': '강남역',
      'address': '서울특별시 강남구 강남대로 396',
      'lat': 37.4979,
      'lng': 127.0276,
    },
    {
      'title': '홍대입구역',
      'address': '서울특별시 마포구 양화로 188',
      'lat': 37.5563,
      'lng': 126.9226,
    },
    {'title': '명동', 'address': '서울특별시 중구 명동', 'lat': 37.5636, 'lng': 126.9826},
    {
      'title': '이태원',
      'address': '서울특별시 용산구 이태원동',
      'lat': 37.5347,
      'lng': 126.9947,
    },
  ];

  @override
  void initState() {
    super.initState();
    // 기본값 설정
    _latController.text = '37.5665';
    _lngController.text = '126.9780';
    _titleController.text = '서울시청';
    _addressController.text = '서울특별시 중구 세종대로 110';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  '위치 선택',
                  style: TextStyle(
                    color: AppColors.darkTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.darkTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 미리 정의된 위치 목록
            const Text(
              '인기 위치',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView.builder(
                itemCount: _predefinedLocations.length,
                itemBuilder: (context, index) {
                  final location = _predefinedLocations[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.darkBorder, width: 1),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.place,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      title: Text(
                        location['title'],
                        style: const TextStyle(
                          color: AppColors.darkTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        location['address'],
                        style: const TextStyle(
                          color: AppColors.darkTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        _selectLocation(location);
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // 수동 입력 섹션
            const Text(
              '직접 입력',
              style: TextStyle(
                color: AppColors.darkTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),

            // 제목 입력
            TextField(
              controller: _titleController,
              style: const TextStyle(color: AppColors.darkTextPrimary),
              decoration: InputDecoration(
                labelText: '제목',
                labelStyle: const TextStyle(color: AppColors.darkTextSecondary),
                filled: true,
                fillColor: AppColors.darkSurfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.darkBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 주소 입력
            TextField(
              controller: _addressController,
              style: const TextStyle(color: AppColors.darkTextPrimary),
              decoration: InputDecoration(
                labelText: '주소',
                labelStyle: const TextStyle(color: AppColors.darkTextSecondary),
                filled: true,
                fillColor: AppColors.darkSurfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.darkBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 좌표 입력
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    style: const TextStyle(color: AppColors.darkTextPrimary),
                    decoration: InputDecoration(
                      labelText: '위도',
                      labelStyle: const TextStyle(
                        color: AppColors.darkTextSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.darkSurfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.darkBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.darkBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    style: const TextStyle(color: AppColors.darkTextPrimary),
                    decoration: InputDecoration(
                      labelText: '경도',
                      labelStyle: const TextStyle(
                        color: AppColors.darkTextSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.darkSurfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.darkBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AppColors.darkBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 확인 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirmSelection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '위치 추가',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectLocation(Map<String, dynamic> location) {
    setState(() {
      _titleController.text = location['title'];
      _addressController.text = location['address'];
      _latController.text = location['lat'].toString();
      _lngController.text = location['lng'].toString();
    });
  }

  void _confirmSelection() {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('올바른 좌표를 입력해주세요.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    widget.onLocationSelected(
      lat,
      lng,
      _titleController.text,
      _addressController.text,
    );

    Navigator.of(context).pop();
  }
}
