//
//  ModelDataHandler.swift
//  SmartCamera
//
//  Created by KillerBe on 11.11.2019.
//  Copyright © 2019 Dima Khymych. All rights reserved.
//

import CoreImage
import TensorFlowLite
import UIKit


/// Stores results for a particular frame that was successfully run through the `Interpreter`.
struct Result {
  let inferenceTime: Double
  let inferences: [Inference]
}

/// Stores one formatted inference.
struct Inference {
  let confidence: Float
  let className: String
  let rect: CGRect
  let displayColor: UIColor
}

/// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

/// Information about the MobileNet SSD model.
enum MobileNetSSD {
  static let modelInfo: FileInfo = (name: "detect", extension: "tflite")
  static let labelsInfo: FileInfo = (name: "labelmap", extension: "txt")
}

/// This class handles all data preprocessing and makes calls to run inference on a given frame
/// by invoking the `Interpreter`. It then formats the inferences obtained and returns the top N
/// results for a successful inference.
class ModelDataHandler: NSObject {

  // MARK: - Internal Properties
  /// The current thread count used by the TensorFlow Lite Interpreter.
  let threadCount: Int
  let threadCountLimit = 10

  let threshold: Float = 0.5

  // MARK: Model parameters
  let batchSize = 1
  let inputChannels = 3
  let inputWidth = 300
  let inputHeight = 300

  // MARK: Private properties
  private var labels: [String] = []

  /// TensorFlow Lite `Interpreter` object for performing inference on a given model.
  private var interpreter: Interpreter

  private let bgraPixel = (channels: 4, alphaComponent: 3, lastBgrComponent: 2)
  private let rgbPixelChannels = 3
  private let colorStrideValue = 10
  private let colors = [
    UIColor.red,
    UIColor(displayP3Red: 90.0/255.0, green: 200.0/255.0, blue: 250.0/255.0, alpha: 1.0),
    UIColor.green,
    UIColor.orange,
    UIColor.blue,
    UIColor.purple,
    UIColor.magenta,
    UIColor.yellow,
    UIColor.cyan,
    UIColor.brown
  ]

  // MARK: - Initialization
  /// A failable initializer for `ModelDataHandler`. A new instance is created if the model and
  /// labels files are successfully loaded from the app's main bundle. Default `threadCount` is 1.
  init?(modelFileInfo: FileInfo, labelsFileInfo: FileInfo, threadCount: Int = 1) {
    let modelFilename = modelFileInfo.name

    // Construct the path to the model file.
    guard let modelPath = Bundle.main.path(
      forResource: modelFilename,
      ofType: modelFileInfo.extension
    ) else {
      print("Failed to load the model file with name: \(modelFilename).")
      return nil
    }

    // Specify the options for the `Interpreter`.
    self.threadCount = threadCount
    var options = InterpreterOptions()
    options.threadCount = threadCount
    do {
      // Create the `Interpreter`.
      interpreter = try Interpreter(modelPath: modelPath, options: options)
      // Allocate memory for the model's input `Tensor`s.
      try interpreter.allocateTensors()
    } catch let error {
      print("Failed to create the interpreter with error: \(error.localizedDescription)")
      return nil
    }

    super.init()

    // Load the classes listed in the labels file.
    loadLabels(fileInfo: labelsFileInfo)
  }

  /// This class handles all data preprocessing and makes calls to run inference on a given frame
  /// through the `Interpeter`. It then formats the inferences obtained and returns the top N
  /// results for a successful inference.
  func runModel(onFrame pixelBuffer: CVPixelBuffer) -> Result? {
    let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
    let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
    
    //MARK: Chek me later
    
    _ = CVPixelBufferGetPixelFormatType(pixelBuffer)
    
    let imageChannels = 4
    assert(imageChannels >= inputChannels)
    
    
    
    
    // Crops the image to the biggest square in the center and scales it down to model dimensions.
    let scaledSize = CGSize(width: inputWidth, height: inputHeight)
    guard let scaledPixelBuffer = pixelBuffer.resized(to: scaledSize) else {
      return nil
    }

    let interval: TimeInterval
    let outputBoundingBox: Tensor
    let outputClasses: Tensor
    let outputScores: Tensor
    let outputCount: Tensor
    do {
      let inputTensor = try interpreter.input(at: 0)

      // Remove the alpha component from the image buffer to get the RGB data.
      guard let rgbData = rgbDataFromBuffer(
        scaledPixelBuffer,
        byteCount: batchSize * inputWidth * inputHeight * inputChannels,
        isModelQuantized: inputTensor.dataType == .uInt8
      ) else {
        print("Failed to convert the image buffer to RGB data.")
        return nil
      }

      // Copy the RGB data to the input `Tensor`.
      try interpreter.copy(rgbData, toInputAt: 0)

      // Run inference by invoking the `Interpreter`.
      let startDate = Date()
      try interpreter.invoke()
      interval = Date().timeIntervalSince(startDate) * 1000

      outputBoundingBox = try interpreter.output(at: 0)
      outputClasses = try interpreter.output(at: 1)
      outputScores = try interpreter.output(at: 2)
      outputCount = try interpreter.output(at: 3)
    } catch let error {
      print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
      return nil
    }

    // Formats the results
    let resultArray = formatResults(
      boundingBox: [Float](unsafeData: outputBoundingBox.data) ?? [],
      outputClasses: [Float](unsafeData: outputClasses.data) ?? [],
      outputScores: [Float](unsafeData: outputScores.data) ?? [],
      outputCount: Int(([Float](unsafeData: outputCount.data) ?? [0])[0]),
      width: CGFloat(imageWidth),
      height: CGFloat(imageHeight)
    )

    // Returns the inference time and inferences
    let result = Result(inferenceTime: interval, inferences: resultArray)
    return result
  }

  /// Filters out all the results with confidence score < threshold and returns the top N results
  /// sorted in descending order.
  func formatResults(boundingBox: [Float], outputClasses: [Float], outputScores: [Float], outputCount: Int, width: CGFloat, height: CGFloat) -> [Inference]{
    var resultsArray: [Inference] = []
    if (outputCount == 0) {
      return resultsArray
    }
    for i in 0...outputCount - 1 {

      let score = outputScores[i]

      // Filters results with confidence < threshold.
      guard score >= threshold else {
        continue
      }

      // Gets the output class names for detected classes from labels list.
      let outputClassIndex = Int(outputClasses[i])
      let outputClass = labels[outputClassIndex + 1]

      var rect: CGRect = CGRect.zero

      // Translates the detected bounding box to CGRect.
      rect.origin.y = CGFloat(boundingBox[4*i])
      rect.origin.x = CGFloat(boundingBox[4*i+1])
      rect.size.height = CGFloat(boundingBox[4*i+2]) - rect.origin.y
      rect.size.width = CGFloat(boundingBox[4*i+3]) - rect.origin.x

      // The detected corners are for model dimensions. So we scale the rect with respect to the
      // actual image dimensions.
      let newRect = rect.applying(CGAffineTransform(scaleX: width, y: height))

      // Gets the color assigned for the class
      let colorToAssign = colorForClass(withIndex: outputClassIndex + 1)
      let inference = Inference(confidence: score,
                                className: outputClass,
                                rect: newRect,
                                displayColor: colorToAssign)
      resultsArray.append(inference)
    }

    // Sort results in descending order of confidence.
    resultsArray.sort { (first, second) -> Bool in
      return first.confidence  > second.confidence
    }

    return resultsArray
  }

  /// Loads the labels from the labels file and stores them in the `labels` property.
  private func loadLabels(fileInfo: FileInfo) {
    let filename = fileInfo.name
    let fileExtension = fileInfo.extension
    guard let fileURL = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
      fatalError("Labels file not found in bundle. Please add a labels file with name " +
                   "\(filename).\(fileExtension) and try again.")
    }
    do {
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      labels = contents.components(separatedBy: .newlines)
    } catch {
      fatalError("Labels file named \(filename).\(fileExtension) cannot be read. Please add a " +
                   "valid labels file and try again.")
    }
  }

  /// Returns the RGB data representation of the given image buffer with the specified `byteCount`.
  ///
  /// - Parameters
  ///   - buffer: The BGRA pixel buffer to convert to RGB data.
  ///   - byteCount: The expected byte count for the RGB data calculated using the values that the
  ///       model was trained on: `batchSize * imageWidth * imageHeight * componentsCount`.
  ///   - isModelQuantized: Whether the model is quantized (i.e. fixed point values rather than
  ///       floating point values).
  /// - Returns: The RGB data representation of the image buffer or `nil` if the buffer could not be
  ///     converted.
  private func rgbDataFromBuffer(
    _ buffer: CVPixelBuffer,
    byteCount: Int,
    isModelQuantized: Bool
  ) -> Data? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let mutableRawPointer = CVPixelBufferGetBaseAddress(buffer) else {
      return nil
    }
//    assert(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA)
    let count = CVPixelBufferGetDataSize(buffer)
    let bufferData = Data(bytesNoCopy: mutableRawPointer, count: count, deallocator: .none)
    var rgbBytes = [UInt8](repeating: 0, count: byteCount)
    var pixelIndex = 0
    for component in bufferData.enumerated() {
      let bgraComponent = component.offset % bgraPixel.channels;
      let isAlphaComponent = bgraComponent == bgraPixel.alphaComponent;
      guard !isAlphaComponent else {
        pixelIndex += 1
        continue
      }
      // Swizzle BGR -> RGB.
      let rgbIndex = pixelIndex * rgbPixelChannels + (bgraPixel.lastBgrComponent - bgraComponent)
      rgbBytes[rgbIndex] = component.element
    }
    if isModelQuantized  { return Data(_: rgbBytes) }
    
    return Data(copyingBufferOf: rgbBytes.map { Float($0) / 255.0 })
  }

  /// This assigns color for a particular class.
  private func colorForClass(withIndex index: Int) -> UIColor {

    // We have a set of colors and the depending upon a stride, it assigns variations to of the base
    // colors to each object based on its index.
  let baseColor = colors[index % colors.count]

    var colorToAssign = baseColor

    let percentage = CGFloat((colorStrideValue / 2 - index / colors.count) * colorStrideValue)

    if let modifiedColor = baseColor.getModified(byPercentage: percentage) {
      colorToAssign = modifiedColor
    }

    return colorToAssign
  }
}


