// Original geometric artwork by Rafael Reverberi for this repository.
// Run: swift assets/render_icon.swift XcodeBuildStatus.dynamiclakeplugin/icon.png
import AppKit
let size = 512
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:size, pixelsHigh:size, bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
NSGradient(starting: NSColor(red:0.055,green:0.10,blue:0.20,alpha:1), ending: NSColor(red:0.12,green:0.32,blue:0.61,alpha:1))!
    .draw(in:NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)),angle:60)
// A diagonal workshop hammer: simple independent geometry, no Apple artwork or SF Symbol raster.
let transform = AffineTransform(translationByX: 260, byY: 244)
var rotation = AffineTransform(); rotation.rotate(byDegrees: -38)
let handle = NSBezierPath(roundedRect:NSRect(x:-20,y:-155,width:40,height:238),xRadius:10,yRadius:10)
handle.transform(using:rotation); handle.transform(using:transform)
NSColor(red:0.31,green:0.65,blue:0.96,alpha:1).setFill();handle.fill()
let head = NSBezierPath()
head.move(to:NSPoint(x:-106,y:85));head.line(to:NSPoint(x:92,y:85));head.line(to:NSPoint(x:105,y:112))
head.line(to:NSPoint(x:61,y:139));head.line(to:NSPoint(x:8,y:123));head.line(to:NSPoint(x:-106,y:123));head.close()
head.transform(using:rotation);head.transform(using:transform)
NSColor(red:0.91,green:0.95,blue:1,alpha:1).setFill();head.fill()
let badge = NSBezierPath(ovalIn:NSRect(x:347,y:77,width:84,height:84))
NSColor(red:0.23,green:0.79,blue:0.59,alpha:1).setFill();badge.fill()
let check = NSBezierPath(); check.move(to:NSPoint(x:369,y:117));check.line(to:NSPoint(x:384,y:101));check.line(to:NSPoint(x:409,y:136))
check.lineWidth = 8;check.lineCapStyle = .round;check.lineJoinStyle = .round;NSColor.white.setStroke();check.stroke()
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using:.png,properties:[:])!
try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
