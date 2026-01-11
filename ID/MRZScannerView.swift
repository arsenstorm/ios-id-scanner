import SwiftUI

struct MRZScannerView: UIViewControllerRepresentable {
  let onValidMRZ: (String, MRZResult) -> Void

  func makeUIViewController(context: Context) -> MRZOCRViewController {
    let vc = MRZOCRViewController()
    vc.onMRZ = { mrz in
      // Validate MRZ; if valid, bubble up once.
      guard let res = try? MRZParser.parseAndValidate(mrz), res.checks.isValid else { return }
      onValidMRZ(mrz, res)
    }
    return vc
  }

  func updateUIViewController(_ uiViewController: MRZOCRViewController, context: Context) {}
}
