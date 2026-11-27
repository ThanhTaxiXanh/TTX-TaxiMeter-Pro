import 'dart:convert';

/// Nhom bien (tab trong bang chon): P cam, W nguy hiem, R hieu lenh, I chi dan, S bien phu.
const Map<String, String> signGroupLabels = <String, String>{
  'P': 'Biển cấm',
  'W': 'Nguy hiểm',
  'R': 'Hiệu lệnh',
  'I': 'Chỉ dẫn',
  'S': 'Biển phụ',
};

class CatalogSign {
  const CatalogSign(this.code, this.name, this.group);
  final String code; // vi du P.103a
  final String name; // co the rong neu chua co ten
  final String group; // P | W | R | I | S
}

/// Ma bien theo QCVN 41, vi du P.103a, W.201b, R.E.9b, IE.463a, S.503c.
final RegExp catalogCodePattern = RegExp(r'^(?:[PWRIS]|IE|R\.E)\.\d+[a-z]?$');

bool isCatalogCode(String s) => catalogCodePattern.hasMatch(s);

List<CatalogSign> parseSignCatalog(String jsonText) {
  final List<dynamic> l = jsonDecode(jsonText) as List<dynamic>;
  return l.map((dynamic e) {
    final Map<String, dynamic> m = e as Map<String, dynamic>;
    return CatalogSign(m['code'] as String, m['name'] as String, m['group'] as String);
  }).toList();
}

const String _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const String _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Bo dau tieng Viet + chu thuong de tim kiem.
String foldVi(String s) {
  final StringBuffer b = StringBuffer();
  for (final int r in s.toLowerCase().runes) {
    final String ch = String.fromCharCode(r);
    final int i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b.toString();
}

/// Loc theo nhom va tu khoa (ma hoac ten, khong phan biet dau). Tu khoa rong -> ca nhom.
List<CatalogSign> filterCatalog(List<CatalogSign> all, String group, String query) {
  final String q = foldVi(query.trim()).replaceAll(' ', '');
  return all.where((CatalogSign s) {
    if (s.group != group) return false;
    if (q.isEmpty) return true;
    return foldVi(s.code).replaceAll('.', '').contains(q.replaceAll('.', '')) ||
        foldVi(s.name).replaceAll(' ', '').contains(q);
  }).toList();
}
