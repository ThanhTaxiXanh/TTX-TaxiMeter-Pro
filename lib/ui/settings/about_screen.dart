import 'package:flutter/material.dart';

const String appVersion = '0.1.0+1';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giới thiệu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          Text('TTX TaxiMeter Pro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Phiên bản $appVersion'),
          SizedBox(height: 16),
          Text('• Mọi dữ liệu (chuyến, biểu giá, tài khoản nhận tiền, báo cáo) chỉ lưu trên máy này; ứng dụng không gửi dữ liệu lên máy chủ nào.'),
          SizedBox(height: 8),
          Text('• Bản đồ và mã QR tạo ngay trên máy, không cần mạng.'),
          SizedBox(height: 8),
          Text('• Tiền cước tính bằng số nguyên; sổ cái chuyến bất biến, đổi tiền chỉ qua điều chỉnh có lý do.'),
        ],
      ),
    );
  }
}
