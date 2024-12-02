import CoreML
import CoreImage
import UIKit

public class BackgroundRemoverSwift: NSObject {
    
    private let context = CIContext()
    
    public func getModel() -> DeepLabV3? {
        return try? DeepLabV3(configuration: MLModelConfiguration())
    }
    
    func pixelBufferFromMultiArray(_ multiArray: MLMultiArray, width: Int, height: Int) -> CVPixelBuffer? {
        let pointer = multiArray.dataPointer.bindMemory(to: UInt8.self, capacity: multiArray.count)
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, attributes as CFDictionary, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let pixelBufferPointer = CVPixelBufferGetBaseAddress(buffer)
        memcpy(pixelBufferPointer, pointer, multiArray.count)
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        
        return buffer
    }
    
    @objc
    public func removeBackground(_ imageURI: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
        #if targetEnvironment(simulator)
        reject("BackgroundRemover", "SimulatorError", NSError(domain: "BackgroundRemover", code: 2))
        return
        #endif

        guard let model = getModel() else {
            reject("BackgroundRemover", "Model loading error", NSError(domain: "BackgroundRemover", code: 8))
            return
        }
        
        guard let url = URL(string: imageURI),
              let originalImage = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            reject("BackgroundRemover", "Invalid or unreadable image URL", NSError(domain: "BackgroundRemover", code: 3))
            return
        }
        
        guard let pixelBuffer = createPixelBuffer(from: originalImage) else {
            reject("BackgroundRemover", "Unable to create pixel buffer", NSError(domain: "BackgroundRemover", code: 4))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let prediction = try model.prediction(fromImage: pixelBuffer)
                let multiArray = prediction.semanticPredictions
                
                // Convert MLMultiArray to CVPixelBuffer
                let width = Int(originalImage.extent.width)
                let height = Int(originalImage.extent.height)
                guard let segmentationBuffer = self.pixelBufferFromMultiArray(multiArray, width: width, height: height) else {
                    DispatchQueue.main.async {
                        reject("BackgroundRemover", "Error converting MLMultiArray to CVPixelBuffer", NSError(domain: "BackgroundRemover", code: 5))
                    }
                    return
                }
                
                // Convert segmentationBuffer into Data or CIImage
                let maskImage = CIImage(cvPixelBuffer: segmentationBuffer)
                let maskData = self.context.pngRepresentation(of: maskImage, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                
                DispatchQueue.main.async {
                    guard let maskImageData = maskData else {
                        reject("BackgroundRemover", "Error creating mask image data", NSError(domain: "BackgroundRemover", code: 6))
                        return
                    }
                    
                    do {
                        guard let cgMaskedImage = self.context.createCGImage(maskImage, from: maskImage.extent) else {
                            throw NSError(domain: "BackgroundRemover", code: 7, userInfo: [NSLocalizedDescriptionKey: "Error creating CGImage"])
                        }
                        
                        let uiImage = UIImage(cgImage: cgMaskedImage)
                        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(url.lastPathComponent).appendingPathExtension("png")
                        
                        if let data = uiImage.pngData() {
                            try data.write(to: tempURL)
                            resolve(tempURL.absoluteString)
                        } else {
                            throw NSError(domain: "BackgroundRemover", code: 8, userInfo: [NSLocalizedDescriptionKey: "Error saving image"])
                        }
                    } catch {
                        reject("BackgroundRemover", "Error handling image", error)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    reject("BackgroundRemover", "Error during background removal", error)
                }
            }
        }
    }
    
    private func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        context.render(ciImage, to: buffer)
        return buffer
    }
}
