//
//  HRColorPicker.swift
//  ColorPicker3
//
//  Created by Hayashi Ryota on 2019/02/16.
//  Copyright © 2019 Hayashi Ryota. All rights reserved.
//

import UIKit

public class ColorPickerStyle: NSObject, NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        return ColorPickerStyle.init(slideShadowBgColor: self.sliderShadowBgColor)
    }
    
    public var sliderShadowBgColor: UIColor
    public var sliderSeparatorColor: UIColor
    
    init(slideShadowBgColor: UIColor? = nil, slideSeparatorColor: UIColor? = nil) {
        if let color = slideShadowBgColor {
            self.sliderShadowBgColor = color
        } else {
            self.sliderShadowBgColor = {
                let bgColor: UIColor
                if #available(iOS 13.0, *) {
                    bgColor = UIColor.systemBackground
                } else {
                    bgColor = UIColor.white
                }
                return bgColor
            }()
        }
        
        if let color = slideSeparatorColor {
            self.sliderSeparatorColor = color
        } else {
            self.sliderSeparatorColor = {
                let separatorColor: UIColor
                if #available(iOS 13.0, *) {
                    separatorColor = UIColor.tertiarySystemGroupedBackground
                } else {
                    separatorColor = #colorLiteral(red: 0.8940519691, green: 0.894156158, blue: 0.8940039277, alpha: 1)
                }
                return separatorColor
            }()
        }
        super.init()
    }
}

public final class ColorPicker: UIControl {
    
    private(set) lazy var colorSpace: HRColorSpace = { preconditionFailure() }()

    public var color: UIColor {
        get {
            return hsvColor.uiColor
        }
    }
    
    @objc @NSCopying public dynamic var style: ColorPickerStyle = ColorPickerStyle() {
        didSet {
            if self.style.sliderShadowBgColor != self.brightnessSlider.sliderShadowBackgroundColor {
                self.brightnessSlider.sliderShadowBackgroundColor = self.style.sliderShadowBgColor
            }
            if self.style.sliderSeparatorColor != self.brightnessSlider.sliderSeparatorColor {
                self.brightnessSlider.sliderSeparatorColor = self.style.sliderSeparatorColor
            }
        }
    }

    private let brightnessCursor = BrightnessCursor()
    private var brightnessSlider = BrightnessSlider()
    private let colorMap = ColorMapView()
    private let colorMapCursor = ColorMapCursor()

    private lazy var hsvColor: HSVColor = { preconditionFailure() }()

    private let feedbackGenerator = UISelectionFeedbackGenerator()
    
    private var tapGesture: UITapGestureRecognizer?
    private var panGesture: UIPanGestureRecognizer?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        addSubview(colorMap)
        addSubview(brightnessSlider)
        addSubview(brightnessCursor)
        addSubview(colorMapCursor)

        let colorMapPan = UIPanGestureRecognizer(target: self, action: #selector(self.handleColorMapPan(pan:)))
        colorMapPan.delegate = self
        self.panGesture = colorMapPan
        colorMap.addGestureRecognizer(colorMapPan)

        let colorMapTap = UITapGestureRecognizer(target: self, action: #selector(self.handleColorMapTap(tap:)))
        colorMapTap.delegate = self
        self.tapGesture = colorMapTap
        colorMap.addGestureRecognizer(colorMapTap)

        brightnessSlider.delegate = self
        brightnessSlider.sliderShadowBackgroundColor = self.style.sliderShadowBgColor
        brightnessSlider.sliderSeparatorColor = self.style.sliderSeparatorColor

        feedbackGenerator.prepare()
    }

    public func set(color: UIColor, colorSpace: HRColorSpace) {
        self.colorSpace = colorSpace
        colorMap.colorSpace = colorSpace
        hsvColor = HSVColor(color: color, colorSpace: colorSpace)
        if superview != nil {
            mapColorToView(initialize: true)
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()

        let margin: CGFloat = 12
        let brightnessSliderWidth: CGFloat = 72
        let colorMapSize = min(bounds.width - brightnessSliderWidth - margin * 3, bounds.height - 2 * margin)

        let colorMapX = (bounds.width - (colorMapSize + margin * 2 + brightnessSliderWidth)) / 2

        colorMap.frame = CGRect(x: colorMapX, y: (bounds.height - colorMapSize)/2, width: colorMapSize + margin * 2, height: colorMapSize)
        brightnessSlider.frame = CGRect(x: colorMap.frame.maxX, y: (bounds.height - colorMapSize)/2,
                                        width: brightnessSliderWidth, height: colorMapSize)

        let brightnessCursorSize = CGSize(width: brightnessSliderWidth, height: 28)
        brightnessCursor.frame = CGRect(x: colorMap.frame.maxX,
                                        y: (bounds.height - brightnessCursorSize.height)/2,
                                        width: brightnessCursorSize.width, height: brightnessCursorSize.height)
        mapColorToView(initialize: true)
    }
    
    private func mapColorToView(initialize: Bool = false) {
        brightnessCursor.set(hsv: hsvColor)
        colorMap.set(brightness: hsvColor.brightness)
        colorMapCursor.center =  colorMap.convert(colorMap.position(for: hsvColor.hueAndSaturation), to: self)
        colorMapCursor.set(hsvColor: hsvColor)
        brightnessSlider.set(hsColor: hsvColor.hueAndSaturation)
        if initialize {
            self.brightnessSlider.set(brightness: self.hsvColor.brightness)
        }
    }
    
    @objc
    private func handleColorMapPan(pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            colorMapCursor.startEditing()
        case .cancelled, .ended, .failed:
            colorMapCursor.endEditing()
        default:
            break
        }
        let selected = colorMap.color(at: pan.location(in: colorMap))
        hsvColor = selected.with(brightness: hsvColor.brightness)
        mapColorToView()
        feedbackIfNeeds()
        sendActionIfNeeds()
    }

    @objc
    private func handleColorMapTap(tap: UITapGestureRecognizer) {
        let selectedColor = colorMap.color(at: tap.location(in: colorMap))
        hsvColor = selectedColor.with(brightness: hsvColor.brightness)
        mapColorToView()
        feedbackIfNeeds()
        sendActionIfNeeds()
    }

    private var prevFeedbackedHSV: HSVColor?
    private func feedbackIfNeeds() {
        if prevFeedbackedHSV != hsvColor {
            feedbackGenerator.selectionChanged()
            prevFeedbackedHSV = hsvColor
        }
    }

    // ↑似た構造ではあるのだが、本質的に異なるので分けた
    private var prevSentActionHSV: HSVColor?
    private func sendActionIfNeeds() {
        if prevSentActionHSV != hsvColor {
            sendActions(for: .valueChanged)
            prevSentActionHSV = hsvColor
        }
    }
}

extension ColorPicker: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view == colorMap, otherGestureRecognizer.view == colorMap {
            return true
        }
        
        return false
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == self.tapGesture, otherGestureRecognizer == self.panGesture {
            return true
        }
        return false
    }
}

extension ColorPicker: BrightnessSliderDelegate {
    func handleBrightnessChanged(slider: BrightnessSlider) {
        hsvColor = hsvColor.hueAndSaturation.with(brightness: slider.brightness)
        mapColorToView()
        feedbackIfNeeds()
        sendActionIfNeeds()
    }
}

extension ColorPicker {
    public static func setupDefaultAppearance() {
        let appearance = Self.appearance()
        appearance.style = ColorPickerStyle()
    }
}
