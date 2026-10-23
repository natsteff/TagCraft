import SwiftUI

struct EditSelectedTagsIcon: View {
    var body: some View {
        Canvas { context, _ in
            let tag = Path(roundedRect: CGRect(x: 1, y: 3, width: 18, height: 12), cornerRadius: 2)
            context.stroke(tag, with: .foreground, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            var lettering = Path()
            lettering.move(to: CGPoint(x: 4, y: 7)); lettering.addLine(to: CGPoint(x: 14, y: 7))
            lettering.move(to: CGPoint(x: 4, y: 11)); lettering.addLine(to: CGPoint(x: 9, y: 11))
            context.stroke(lettering, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            // Knock out the name-tag edge behind the marker to retain a clear silhouette.
            var marker = Path()
            marker.move(to: CGPoint(x: 12, y: 17)); marker.addLine(to: CGPoint(x: 19, y: 10))
            context.stroke(marker, with: .color(Color(nsColor: .windowBackgroundColor)), style: StrokeStyle(lineWidth: 6, lineCap: .square))
            var pen = Path()
            pen.move(to: CGPoint(x: 11, y: 19)); pen.addLine(to: CGPoint(x: 12, y: 15))
            pen.addLine(to: CGPoint(x: 19, y: 8)); pen.addLine(to: CGPoint(x: 22, y: 11))
            pen.addLine(to: CGPoint(x: 15, y: 18)); pen.closeSubpath()
            pen.move(to: CGPoint(x: 17.5, y: 9.5)); pen.addLine(to: CGPoint(x: 20.5, y: 12.5))
            context.stroke(pen, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }.frame(width: 24, height: 21).accessibilityHidden(true)
    }
}

struct FilenameToTagsIcon: View {
 var body: some View {
  Canvas { context,_ in
   var source=Path()
    source.move(to:CGPoint(x:1,y:1));source.addLine(to:CGPoint(x:9,y:1));source.addLine(to:CGPoint(x:13,y:5));source.addLine(to:CGPoint(x:13,y:15));source.addLine(to:CGPoint(x:1,y:15));source.closeSubpath()
    source.move(to:CGPoint(x:9,y:1));source.addLine(to:CGPoint(x:9,y:5));source.addLine(to:CGPoint(x:13,y:5))
    for y in [8.0,11.0] {source.move(to:CGPoint(x:4,y:y));source.addLine(to:CGPoint(x:9,y:y))}
   context.stroke(source,with:.foreground,style:StrokeStyle(lineWidth:1.3,lineCap:.round,lineJoin:.round))
   var arrow=Path();arrow.move(to:CGPoint(x:14,y:7));arrow.addLine(to:CGPoint(x:19,y:12));arrow.move(to:CGPoint(x:19,y:8));arrow.addLine(to:CGPoint(x:19,y:12));arrow.addLine(to:CGPoint(x:15,y:12))
   context.stroke(arrow,with:.foreground,style:StrokeStyle(lineWidth:1.4,lineCap:.round,lineJoin:.round))
   var tag=Path();tag.move(to:CGPoint(x:16,y:16));tag.addLine(to:CGPoint(x:19,y:13));tag.addLine(to:CGPoint(x:25,y:13));tag.addLine(to:CGPoint(x:25,y:19));tag.addLine(to:CGPoint(x:19,y:25));tag.addLine(to:CGPoint(x:13,y:19));tag.closeSubpath()
   context.stroke(tag,with:.foreground,style:StrokeStyle(lineWidth:1.3,lineCap:.round,lineJoin:.round))
   context.fill(Path(ellipseIn:CGRect(x:21,y:15,width:1.5,height:1.5)),with:.foreground)
  }.frame(width:27,height:27)
 }
}

struct RenameFromTagsIcon: View {
 var body: some View {
  ZStack {
   Image(systemName:"tag").font(.system(size:14)).offset(y:0.5)
   Canvas { context,_ in
    var p=Path();p.addArc(center:CGPoint(x:14,y:14),radius:12,startAngle:.degrees(-55),endAngle:.degrees(255),clockwise:false)
    context.stroke(p,with:.foreground,style:StrokeStyle(lineWidth:1.4,lineCap:.round))
    var head=Path();head.move(to:CGPoint(x:7,y:4));head.addLine(to:CGPoint(x:11,y:2));head.addLine(to:CGPoint(x:10,y:7))
    context.stroke(head,with:.foreground,style:StrokeStyle(lineWidth:1.4,lineCap:.round,lineJoin:.round))
   }.frame(width:28,height:28)
  }.frame(width:29,height:29)
 }
}
