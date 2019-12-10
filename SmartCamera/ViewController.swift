//
//  ViewController.swift
//  SmartCamera
//
//  Created by Dima Khymych on 09.11.2019.
//  Copyright © 2019 Dima Khymych. All rights reserved.
//

import UIKit
import AVKit

@available(iOS 13.0, *)
class ViewController: UIViewController {
    
   
    //MARK: - Extended
    private let overlayView = OverlayView()
    private var modelDataHandler: ModelDataHandler? = ModelDataHandler(modelFileInfo: MobileNetSSD.modelInfo, labelsFileInfo: MobileNetSSD.labelsInfo)
    private var result: Result?
    private var captureImage : UIImage?
    
    
    //MARK: - Constans
    private var edgeOffset: CGFloat = 2.0
    private let displayFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
    
    //MARK: - Captures
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var previewLayer : AVCaptureVideoPreviewLayer!
    private var videoDeviceInput: AVCaptureDeviceInput!
    
    
    //MARK: - ViewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard modelDataHandler != nil else {fatalError("Kek")}
       
        sessionQueue.async {
            DispatchQueue.main.async {
                self.configureSession()
            }
            
            
        }
    }
    
    
    //MARK: - ViewWillApear
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async {
            DispatchQueue.main.async {
                self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                self.previewLayer.frame = self.view.bounds
                self.view.layer.addSublayer(self.previewLayer)
                self.captureSession.startRunning()
                
                self.overlayViewConfiguration(self.overlayView)
                
            }
            
        }
        
        
        
    }
    
    
    //MARK: - ViewWillDesapear
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sessionQueue.async {
            self.captureSession.stopRunning()
        }
        
    }
    
    
    //MARK: - RunModel and draw ovarlayView
    //This method runs the live camera pixelBuffer through tensorFlow to get the result.
    // Run the live camera pixelBuffer through tensorFlow to get the result
    
    func runModel(onPixelBuffer pixelBuffer: CVPixelBuffer) {
            
        result = self.modelDataHandler?.runModel(onFrame: pixelBuffer)
            
        guard let displayResult = result else {
                return
        }
            
        let width = CVPixelBufferGetWidth(pixelBuffer)
        
        let height = CVPixelBufferGetHeight(pixelBuffer)
    
    
        self.chekResultAndTakeShot(results: displayResult, captureSession: self.captureSession)
        
        
        
        DispatchQueue.main.async {

            // Draws the bounding boxes and displays class names and confidence scores.
            self.drawAfterPerformingCalculations(onInferences: displayResult.inferences, withImageSize:CGSize(width:CGFloat(width), height:CGFloat(height)))

            }
    }
        
    func chekResultAndTakeShot (results:Result, captureSession: AVCaptureSession) {
        
        
        for result in results.inferences {
            
            let confidense = result.confidence
           
                if confidense >= 0.9 {
                
                    capturePhoto()
            
                        if captureImage != nil {
                            savePhoto()
                    }
                   
                   
            }
            
            
        }
    }
    
    //MARK: - Configuration AVCaptureSessuion
     
      func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        // Add videoinput
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {return}
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else {return}
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
                   }
        
        // Add photo output

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        }
      
        // Add video output
      
      if captureSession.canAddOutput(videoDataOutput) {
          captureSession.addOutput(videoDataOutput)
          videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
          videoDataOutput.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA]
          videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
          
      }
      
        captureSession.commitConfiguration()
    }
    
    // This method configurated photo
    
    func capturePhoto() {

        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true

        if let firstAvailablePreviewPhotoPixelFormatTypes = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
            photoSettings.previewPhotoFormat = [String(kCVPixelBufferPixelFormatTypeKey):firstAvailablePreviewPhotoPixelFormatTypes]
        }
    
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
        
    }
    
    //MARK: - Image piker for save
    
    
    func createPicker () {
        
        let imgPicker = UIImagePickerController()
               imgPicker.delegate = self
               imgPicker.sourceType = .camera
    }
    
    
    func savePhoto ()  {
        
        guard let selectedImage = self.captureImage else {
            print("Image not found!")
            return
        }
        UIImageWriteToSavedPhotosAlbum(selectedImage, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
        captureSession.stopRunning()
    }
    
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if error != nil {
            print( "Save error")
        } else {
            print( "Saved! Your image has been saved to your photos.")
        }
    }
          
    
    //This method takes the results, translates the bounding box rects to the current view, draws the bounding boxes, classNames and confidence scores of inferences.
           
          func drawAfterPerformingCalculations(onInferences inferences: [Inference], withImageSize imageSize:CGSize) {

            self.overlayView.objectOverlays = []
            
            self.overlayView.setNeedsDisplay()

            guard !inferences.isEmpty else {
              return
            }

            var objectOverlays: [ObjectOverlay] = []
            

            for inference in inferences {

            // Translates bounding box rect to current view.
                var convertedRect = inference.rect.applying(CGAffineTransform(scaleX:self.overlayView.bounds.size.width / imageSize.width, y:self.overlayView.bounds.size.height / imageSize.height))

              if convertedRect.origin.x < 0 {
                convertedRect.origin.x = self.edgeOffset
                
              }

              if convertedRect.origin.y < 0 {
                convertedRect.origin.y = self.edgeOffset
              }

              if convertedRect.maxY > self.overlayView.bounds.maxY {
                convertedRect.size.height = self.overlayView.bounds.maxY - convertedRect.origin.y - self.edgeOffset
              }

              if convertedRect.maxX > self.overlayView.bounds.maxX {
                convertedRect.size.width = self.overlayView.bounds.maxX - convertedRect.origin.x - self.edgeOffset
              }

              let confidenceValue = Int(inference.confidence * 100.0)
            let string:String = "\(inference.className)  (\(confidenceValue)%)"
                
                let size = string.size(usingFont: self.displayFont)
              let objectOverlay = ObjectOverlay(name:string, borderRect:convertedRect, nameStringSize:size, color:inference.displayColor, font:self.displayFont)

              objectOverlays.append(objectOverlay)
            }

            // Hands off drawing to the OverlayView
            self.draw(objectOverlays: objectOverlays)

          }

          // Calls methods to update overlay view with detected bounding boxes and class names.
           
          func draw(objectOverlays: [ObjectOverlay]) {

            self.overlayView.objectOverlays = objectOverlays
            self.overlayView.setNeedsDisplay()
    
    }
    
    
    
    

    
    
}
// MARK: - Etension

@available(iOS 13.0, *)
extension ViewController:AVCaptureVideoDataOutputSampleBufferDelegate,AVCapturePhotoCaptureDelegate ,UIImagePickerControllerDelegate,UINavigationControllerDelegate{
    
   func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]){
          guard let selectedImage = info[.originalImage] as? UIImage else {
              print("Image not found!")
              return
          }
    self.captureImage = selectedImage
      }
    
    
    // Add overlayView on the ViewController
    func overlayViewConfiguration(_ overlayView:UIView) {
         overlayView.frame = self.view.frame
               // overlayView.willMove(toSuperview: self.view)
                overlayView.clearsContextBeforeDrawing = true
                overlayView.backgroundColor = UIColor.clear
                overlayView.didMoveToSuperview()
                 self.view.addSubview(overlayView)
     }
     
//MARK:- Methods of protocol and delegat
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {

        guard let data = photo.fileDataRepresentation(),
              let image =  UIImage(data: data)  else {
                return
        }
        self.captureImage = image
          }
    
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
     
            self.runModel(onPixelBuffer:pixelBuffer)
        
        
        
    }

}

    
    
    



    

    
    












  
    
    
   

    

