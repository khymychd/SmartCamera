//
//  OverlayView.swift
//  SmartCamera
//
//  Created by KillerBe on 11.11.2019.
//  Copyright © 2019 Dima Khymych. All rights reserved.
//

import UIKit


// This structure holds the display parameters for the overlay to be drawon on a detected object.

struct ObjectOverlay {
  let name: String
  let borderRect: CGRect
  let nameStringSize: CGSize
  let color: UIColor
  let font: UIFont
}


 //This UIView draws overlay on a detected object.
 
class OverlayView: UIView {

  var objectOverlays: [ObjectOverlay] = []
  private let cornerRadius: CGFloat = 10.0
  private let stringBgAlpha: CGFloat
    = 0.7
  private let lineWidth: CGFloat = 3
    private let stringFontColor = UIColor.green
  private let stringHorizontalSpacing: CGFloat = 13.0
  private let stringVerticalSpacing: CGFloat = 7.0
    public var objectDiscription: String = ""
 
    override func draw(_ rect: CGRect) {

    // Drawing code
    for objectOverlay in objectOverlays {

        drawBorders(of: objectOverlay)
      //drawName(of: objectOverlay)
    }
  }
  func drawBorders(of objectOverlay: ObjectOverlay) {

    let path = UIBezierPath(rect: objectOverlay.borderRect)
    path.lineWidth = lineWidth
    objectOverlay.color.setStroke()
    
    path.stroke()
  }


}

