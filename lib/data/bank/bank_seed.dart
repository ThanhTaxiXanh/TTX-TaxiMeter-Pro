// Danh muc ngan hang NHUNG SAN (offline). BIN theo danh muc NAPAS/VietQR.
// Chu xe nen doi chieu BIN voi ngan hang truoc khi dung that (xem CONTEXT_STATE).
class BankSeed {
  const BankSeed(this.bin, this.code, this.shortName);
  final String bin;
  final String code;
  final String shortName;
}

const List<BankSeed> bankSeeds = <BankSeed>[
  BankSeed('970436', 'VCB', 'Vietcombank'),
  BankSeed('970415', 'CTG', 'VietinBank'),
  BankSeed('970418', 'BIDV', 'BIDV'),
  BankSeed('970405', 'AGRIBANK', 'Agribank'),
  BankSeed('970407', 'TCB', 'Techcombank'),
  BankSeed('970422', 'MB', 'MB Bank'),
  BankSeed('970416', 'ACB', 'ACB'),
  BankSeed('970432', 'VPB', 'VPBank'),
  BankSeed('970423', 'TPB', 'TPBank'),
  BankSeed('970403', 'STB', 'Sacombank'),
  BankSeed('970437', 'HDB', 'HDBank'),
  BankSeed('970441', 'VIB', 'VIB'),
  BankSeed('970443', 'SHB', 'SHB'),
  BankSeed('970448', 'OCB', 'OCB'),
  BankSeed('970426', 'MSB', 'MSB'),
  BankSeed('970440', 'SEAB', 'SeABank'),
  BankSeed('970449', 'LPB', 'LPBank'),
  BankSeed('970431', 'EIB', 'Eximbank'),
  BankSeed('970433', 'VIETBANK', 'VietBank'),
  BankSeed('970428', 'NAB', 'Nam A Bank'),
  BankSeed('970425', 'ABB', 'ABBANK'),
  BankSeed('970409', 'BAB', 'Bac A Bank'),
  BankSeed('970412', 'PVCB', 'PVcomBank'),
  BankSeed('970438', 'BVB', 'BaoViet Bank'),
  BankSeed('970419', 'NCB', 'NCB'),
  BankSeed('970429', 'SCB', 'SCB'),
  BankSeed('970452', 'KLB', 'KienlongBank'),
  BankSeed('970400', 'SGICB', 'SaigonBank'),
  BankSeed('970408', 'GPB', 'GPBank'),
  BankSeed('970446', 'COOPBANK', 'Co-opBank'),
  BankSeed('970421', 'VRB', 'VRB'),
  BankSeed('970434', 'IVB', 'Indovina Bank'),
  BankSeed('970424', 'SHBVN', 'Shinhan Bank'),
  BankSeed('970457', 'WVN', 'Woori Bank'),
  BankSeed('970439', 'PBVN', 'Public Bank'),
  BankSeed('970410', 'SCVN', 'Standard Chartered'),
  BankSeed('546034', 'CAKE', 'CAKE by VPBank'),
  BankSeed('546035', 'UBANK', 'Ubank by VPBank'),
  BankSeed('963388', 'TIMO', 'Timo'),
  BankSeed('971005', 'VIETTELMONEY', 'Viettel Money'),
  BankSeed('971011', 'VNPTMONEY', 'VNPT Money'),
];
