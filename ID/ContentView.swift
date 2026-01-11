import SwiftUI
import UIKit

struct ContentView: View {
  private enum ScanStep: Int {
    case welcome
    case rfidCheck
    case nfc
    case result
  }

  private enum NavigationDirection {
    case forward
    case backward
  }

  @State private var step: ScanStep = .welcome
  @State private var navDirection: NavigationDirection = .forward
  @State private var previousStep: ScanStep?
  @State private var transitionProgress: CGFloat = 1
  @State private var mrz: String = ""
  @State private var mrzResult: MRZResult?
  @StateObject private var nfcReader = PassportNFCReader()
  @State private var hasStartedNFC = false
  @State private var isNFCActive = false
  @State private var hasRFIDSymbol: Bool?
  @State private var isMRZLocked = false
  @State private var cameraBlur: CGFloat = 0
  @State private var didTriggerMRZ = false
  @State private var isMRZSheetPresented = false
  private var hasResult: Bool { nfcReader.result != nil }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.white.ignoresSafeArea()

        GeometryReader { geo in
          let width = geo.size.width
          let directionSign: CGFloat = navDirection == .forward ? 1 : -1

          ZStack {
            if let previousStep {
              stepView(for: previousStep)
                .offset(x: -directionSign * width * transitionProgress)
            }

            stepView(for: step)
              .offset(x: directionSign * width * (1 - transitionProgress))
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: step) { newStep in
          if newStep == .nfc {
            guard !hasStartedNFC else { return }
            hasStartedNFC = true
            isNFCActive = true
            nfcReader.start(mrz: mrz)
          }
        }
        .onChange(of: hasResult) { newValue in
          if newValue {
            isNFCActive = false
            setStep(.result)
          }
        }
        .onChange(of: nfcReader.errorMessage) { newValue in
          if newValue != nil {
            isNFCActive = false
          }
        }
      }
    }
    .tint(.black)
    .sheet(isPresented: $isMRZSheetPresented, onDismiss: handleMRZSheetDismiss) {
      CameraPermissionGate(onCancel: {
        isMRZSheetPresented = false
        setStepInstantly(.welcome)
      }) {
        mrzScannerView
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
    }
  }

  @ViewBuilder
  private func stepView(for step: ScanStep) -> some View {
    switch step {
    case .welcome:
      welcomeView
    case .rfidCheck:
      rfidCheckView
    case .nfc:
      nfcView
    case .result:
      resultView
    }
  }

  private var welcomeView: some View {
    VStack(alignment: .leading, spacing: 16) {
      Spacer()

      VStack(alignment: .center, spacing: 12) {
        Image("Logo")
          .resizable()
          .scaledToFit()
          .frame(width: 96, height: 96)
          .clipShape(RoundedRectangle(cornerRadius: 20))
          .overlay(
            RoundedRectangle(cornerRadius: 20)
              .stroke(Color.black.opacity(0.1), lineWidth: 1)
          )

        Text("Let's read your ID")
          .font(.title3).bold()
          .foregroundStyle(.black)

        Text("Use your camera to scan your photo page, then read the chip if it has one.")
          .font(.subheadline)
          .foregroundStyle(.black.opacity(0.6))
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)

      Spacer()

      PrimaryActionButton(title: "Continue") {
        presentMRZSheet()
      }
    }
    .padding(16)
  }

  private var mrzScannerView: some View {
    ZStack {
      MRZScannerView(onValidMRZ: { validMRZ, result in
        guard !didTriggerMRZ else { return }
        didTriggerMRZ = true
        prepareForNewScan()
        mrz = validMRZ
        mrzResult = result
        withAnimation(.easeInOut(duration: 0.25)) {
          isMRZLocked = true
        }
        withAnimation(.easeInOut(duration: 1.0)) {
          cameraBlur = 8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          withAnimation(.easeInOut(duration: 0.25)) {
            isMRZSheetPresented = false
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            setStep(.rfidCheck)
          }
        }
      })
      .ignoresSafeArea()
      .blur(radius: cameraBlur)

      MRZScanOverlayView(isLocked: isMRZLocked)
        .allowsHitTesting(false)

      VStack(spacing: 6) {
        Spacer()
        Text("Scan your photo page")
          .font(.headline)
          .foregroundStyle(.white)

        Text("Align the photo page within the box.")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.85))
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var rfidCheckView: some View {
    VStack(alignment: .center, spacing: 16) {
      Text("Do you see this symbol?")
        .font(.headline)
        .foregroundStyle(.black)

      VStack(spacing: 10) {
        Image("RFIDSymbol")
          .resizable()
          .scaledToFit()
          .frame(maxWidth: 150)
          .accessibilityLabel("RFID symbol")

        Text(rfidHintText)
          .font(.subheadline)
          .foregroundStyle(.black.opacity(0.6))
          .multilineTextAlignment(.center)
      }

      VStack(spacing: 12) {
        PrimaryActionButton(title: rfidPrimaryActionTitle) {
          hasRFIDSymbol = true
          setStep(.nfc)
        }

        PrimaryActionButton(title: "No — skip this step") {
          hasRFIDSymbol = false
          setStep(.result)
        }
      }
      .frame(maxWidth: 360)
    }
    .frame(maxWidth: .infinity)
    .padding(16)
  }

  private var nfcView: some View {
    VStack(alignment: .leading, spacing: 16) {
      Spacer()

      VStack(alignment: .center, spacing: 10) {
        Text(nfcInstructionText)
          .font(.headline)
          .foregroundStyle(.black)
          .multilineTextAlignment(.center)

        Text("This can take up to a minute.")
          .font(.subheadline)
          .foregroundStyle(.black.opacity(0.6))
          .multilineTextAlignment(.center)

        if let error = nfcReader.errorMessage {
          Text(error)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
        } else if !nfcReader.status.isEmpty {
          Text(nfcReader.status)
            .font(.subheadline)
            .foregroundStyle(.black.opacity(0.6))
            .multilineTextAlignment(.center)
        }
      }
      .frame(maxWidth: .infinity)

      Spacer()

      PrimaryActionButton(title: "Try Again") {
        guard !isNFCActive else { return }
        isNFCActive = true
        nfcReader.start(mrz: mrz)
      }
      .disabled(isNFCActive)
      .opacity(isNFCActive ? 0.5 : 1.0)
    }
    .padding(16)
  }

  private var resultView: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let result = nfcReader.result, hasRFIDSymbol == true {
        passportResultView(result)
      } else if let mrzResult {
        mrzResultView(mrzResult, hasRFIDSymbol: hasRFIDSymbol)
      } else {
        Text("No document data available.")
      }

      Spacer()

      PrimaryActionButton(title: "Scan Another ID") {
        resetToMRZ()
      }
    }
    .padding(16)
  }

  private struct MRZScanOverlayView: View {
    let isLocked: Bool
    private let cornerRadius: CGFloat = 12
    private let borderWidth: CGFloat = 6
    private let overlayOpacity: CGFloat = 0.55

    var body: some View {
      GeometryReader { geo in
        let inset: CGFloat = 16
        let windowInsets = windowSafeAreaInsets
        let safeTop = max(geo.safeAreaInsets.top, windowInsets.top)
        let safeLeading = max(geo.safeAreaInsets.leading, windowInsets.left)
        let safeTrailing = max(geo.safeAreaInsets.trailing, windowInsets.right)
        let safeWidth = geo.size.width - safeLeading - safeTrailing
        let boxWidth = max(0, safeWidth - inset * 2)
        let boxHeight = max(0, boxWidth * 0.75)
        let boxTop = safeTop + inset
        let boxCenter = CGPoint(x: geo.size.width / 2, y: boxTop + boxHeight / 2)

        ZStack {
          Color.black.opacity(overlayOpacity)

          RoundedRectangle(cornerRadius: cornerRadius)
            .frame(width: boxWidth, height: boxHeight)
            .position(boxCenter)
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(isLocked ? Color.green : Color.white, lineWidth: borderWidth)
            .frame(width: boxWidth, height: boxHeight)
            .position(boxCenter)
        )
      }
      .ignoresSafeArea()
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
      guard
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let window = scene.windows.first(where: { $0.isKeyWindow })
      else {
        return .zero
      }
      return window.safeAreaInsets
    }
  }

  private func resetToMRZ() {
    isMRZLocked = false
    cameraBlur = 0
    didTriggerMRZ = false
    presentMRZSheet()
  }

  private func handleMRZSheetDismiss() {
    isMRZLocked = false
    cameraBlur = 0
    didTriggerMRZ = false
  }

  private func presentMRZSheet() {
    isMRZLocked = false
    cameraBlur = 0
    didTriggerMRZ = false
    isMRZSheetPresented = true
  }

  private func prepareForNewScan() {
    mrz = ""
    mrzResult = nil
    hasStartedNFC = false
    isNFCActive = false
    nfcReader.result = nil
    nfcReader.errorMessage = nil
    hasRFIDSymbol = nil
  }

  private func setStepInstantly(_ newStep: ScanStep) {
    guard newStep != step else { return }
    navDirection = newStep.rawValue >= step.rawValue ? .forward : .backward
    previousStep = nil
    step = newStep
    transitionProgress = 1
  }


  private func setStep(_ newStep: ScanStep) {
    guard newStep != step else { return }
    navDirection = newStep.rawValue >= step.rawValue ? .forward : .backward
    previousStep = step
    let outgoingStep = previousStep
    step = newStep
    transitionProgress = 0
    withAnimation(.easeInOut(duration: 0.35)) {
      transitionProgress = 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      if previousStep == outgoingStep {
        previousStep = nil
      }
    }
  }

  @ViewBuilder
  private func passportResultView(_ result: PassportReadResult) -> some View {
    VStack(spacing: 20) {
      // Centered photo at top
      if let image = result.passportImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 100, height: 130)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color.black.opacity(0.1), lineWidth: 1)
          )
      }

      // Parsed MRZ fields in rows
      VStack(spacing: 0) {
        fieldRow("First Name", result.firstName)
        fieldRow("Last Name", result.lastName)
        fieldRow("Document Number", result.documentNumber)
        fieldRow("Nationality", result.nationality)
        fieldRow("Date of Birth", formatMRZDate(result.dateOfBirth))
        fieldRow("Sex", formatSex(result.gender))
        fieldRow("Expiry Date", formatMRZDate(result.expiryDate))
        fieldRow("Issuing Country", result.issuingAuthority)
        fieldRow("Document Type", formatDocumentType(result.documentType), isLast: true)
      }
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.black.opacity(0.1), lineWidth: 1)
      )
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func mrzResultView(_ result: MRZResult, hasRFIDSymbol: Bool?) -> some View {
    VStack(spacing: 16) {
      Text("Document details only")
        .font(.headline)
        .foregroundStyle(.black)

      Text(mrzFallbackMessage(hasRFIDSymbol: hasRFIDSymbol))
        .font(.subheadline)
        .foregroundStyle(.black.opacity(0.6))
        .multilineTextAlignment(.center)

      VStack(spacing: 0) {
        fieldRow("First Name", result.givenNames)
        fieldRow("Last Name", result.surnames)
        fieldRow("Document Number", result.documentNumber)
        fieldRow("Nationality", result.nationality)
        fieldRow("Date of Birth", formatMRZDate(result.birthDateYYMMDD))
        fieldRow("Sex", formatSex(result.sex))
        fieldRow("Expiry Date", formatMRZDate(result.expiryDateYYMMDD))
        fieldRow("Issuing Country", result.issuingCountry)
        fieldRow("Document Type", formatDocumentType(result.documentType), isLast: true)
      }
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.black.opacity(0.1), lineWidth: 1)
      )
    }
    .frame(maxWidth: .infinity)
  }

  private func fieldRow(_ label: String, _ value: String, isLast: Bool = false) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text(label)
          .font(.subheadline)
          .foregroundStyle(.black.opacity(0.5))
        Spacer()
        Text(value)
          .font(.subheadline)
          .foregroundStyle(.black)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)

      if !isLast {
        Divider()
          .padding(.leading, 14)
      }
    }
  }

  private func formatMRZDate(_ yymmdd: String) -> String {
    guard yymmdd.count == 6,
          let yy = Int(yymmdd.prefix(2)),
          let mm = Int(yymmdd.dropFirst(2).prefix(2)),
          let dd = Int(yymmdd.suffix(2)) else {
      return yymmdd
    }
    
    // Use pivot: if yy > 50, assume 1900s, else 2000s
    let year = yy > 50 ? 1900 + yy : 2000 + yy
    
    return "\(year)-\(String(format: "%02d", mm))-\(String(format: "%02d", dd))"
  }

  private func formatSex(_ code: String) -> String {
    switch code.uppercased() {
    case "M": return "Male"
    case "F": return "Female"
    default: return "Unspecified"
    }
  }

  private func formatDocumentType(_ code: String) -> String {
    let cleaned = code.replacingOccurrences(of: "<", with: "").trimmingCharacters(in: .whitespaces)
    switch cleaned.uppercased() {
    case "P": return "Passport"
    case "I", "ID": return "ID Card"
    case "V": return "Visa"
    default: return cleaned.isEmpty ? "Unknown" : cleaned
    }
  }

  private var rfidHintText: String = "Look for this symbol on the cover or photo page."

  private var nfcInstructionText: String {
    if let mrzResult, isPassportDocument(mrzResult) {
      return "Keep your iPhone close to your passport."
    }
    return "Keep your iPhone close to your ID."
  }

  private var rfidPrimaryActionTitle: String {
    if let mrzResult, isPassportDocument(mrzResult) {
      return "Yes — scan my Passport"
    }
    return "Yes — scan my ID"
  }

  private func isPassportDocument(_ result: MRZResult) -> Bool {
    if result.format == .td3 {
      return true
    }
    let cleaned = result.documentType.replacingOccurrences(of: "<", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    return cleaned.hasPrefix("P")
  }

  private func mrzFallbackMessage(hasRFIDSymbol: Bool?) -> String {
    switch hasRFIDSymbol {
    case true:
      return "We couldn’t read the chip, so photo data isn’t available."
    case false:
      return "No RFID chip on this document, so photo data isn’t available."
    case .none:
      return "Photo data isn’t available without an RFID chip."
    }
  }
}

private struct PrimaryActionButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(.body, weight: .medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(.white)
        .background(Color.black)
        .clipShape(Capsule())
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
