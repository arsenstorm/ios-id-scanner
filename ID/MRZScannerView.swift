import SwiftUI

struct MRZScannerView: UIViewControllerRepresentable {
  let onValidMRZ: (String, MRZResult, String?) -> Void

  func makeUIViewController(context: Context) -> MRZOCRViewController {
    let vc = MRZOCRViewController()
    vc.onScan = { mrz, can in
      // Validate MRZ; if valid, bubble up once.
      guard let res = try? MRZParser.parseAndValidate(mrz), res.checks.isValid else { return }
      onValidMRZ(mrz, res, can)
    }
    return vc
  }

  func updateUIViewController(_ uiViewController: MRZOCRViewController, context: Context) {}
}
