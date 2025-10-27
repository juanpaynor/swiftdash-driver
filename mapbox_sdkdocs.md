## I don't know if this is gonna be helpful to you but here

Annotations
On this page
Markers
Other shapes
Add annotations to the map using point, line, polygon, and circle shapes using the AnnotationManager with the Mapbox Maps SDK for Flutter. Create annotation managers based on the type of annotation that you're interested in. Every AnnotationManager handles a collection of annotations. Once a manager has been created, you can create and add individually styled instances of the corresponding annotation type.

Benefits:

Built-in interaction support like tapping on annotations.
No external data file necessary.
Every annotation can be individually styled.
Every annotation layer can be adjusted to be above or below another layer.
Same performance benefits as using style layers.
Limitations:

No default image available.
Inefficient for adding many features to the map.
Markers
A PointAnnotation can display any image at a fixed geographic coordinate.

Annotations are added after the initial map is loaded by using the onMapCreated callback. This example loads assets/custom-icon.png and adds it to the map at the coordinates -74.00913, 40.75183 (near New York City):

main.dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State createState() => MyAppState();
  // This widget is the root of your application.
}

class MyAppState extends State<MyApp> {
  late MapboxMap mapboxMap;
  PointAnnotationManager? pointAnnotationManager;

  @override
  _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;
    pointAnnotationManager =
        await mapboxMap.annotations.createPointAnnotationManager();

    // Load the image from assets
    final ByteData bytes =
        await rootBundle.load('assets/custom-icon.png');
    final Uint8List imageData = bytes.buffer.asUint8List();

    // Create a PointAnnotationOptions
    PointAnnotationOptions pointAnnotationOptions = PointAnnotationOptions(
      geometry: Point(coordinates: Position(-74.00913, 40.75183)), // Example coordinates
      image: imageData,
      iconSize: 3.0
    );

    // Add the annotation to the map
    pointAnnotationManager?.create(pointAnnotationOptions);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsFlutterBinding.ensureInitialized();

    // Pass your access token to MapboxOptions so you can load a map
    String ACCESS_TOKEN = const String.fromEnvironment("ACCESS_TOKEN");
    MapboxOptions.setAccessToken(ACCESS_TOKEN);

    // Define options for your camera
    CameraOptions camera = CameraOptions(
        center: Point(coordinates: Position(-74.00913, 40.75183)),
        zoom: 9.6,
        bearing: 0,
        pitch: 30);

    return MaterialApp(
      title: 'Flutter Demo',
      home: MapWidget(
        cameraOptions: camera,
        onMapCreated: _onMapCreated,
      ),
    );
  }
}

Point annotation on an iOS device
Other shapes
The Mapbox Maps SDK for Flutter supports putting other shapes on the map including circles using CircleAnnotationManager, polylines using PolylineAnnotationManager, and polygons using PolygonAnnotationManager. These annotations work like the point annotations described above, but do not require an image. The options available for each type of annotation varies and you can find a full list in the API reference documentation.





PolylineAnnotationManager class
The PolylineAnnotationManager to add/update/delete PolylineAnnotationAnnotations on the map.

Inheritance
Object BaseAnnotationManager PolylineAnnotationManager
Properties
hashCode → int
The hash code for this object.
no setterinherited
id → String
finalinherited
runtimeType → Type
A representation of the runtime type of the object.
no setterinherited
Methods
addOnPolylineAnnotationClickListener(OnPolylineAnnotationClickListener listener) → void
Add a listener to receive the callback when an annotation is clicked.
create(PolylineAnnotationOptions annotation) → Future<PolylineAnnotation>
Create a new annotation with the option.
createMulti(List<PolylineAnnotationOptions> annotations) → Future<List<PolylineAnnotation?>>
Create multi annotations with the options.
delete(PolylineAnnotation annotation) → Future<void>
Delete an added annotation.
deleteAll() → Future<void>
Delete all the annotation added by this manager.
dragEvents({dynamic onBegin(PolylineAnnotation)?, dynamic onChanged(PolylineAnnotation)?, dynamic onEnd(PolylineAnnotation)?}) → Cancelable
Registers drag event callbacks for the annotations managed by this manager.
getLineBlur() → Future<double?>
Blur applied to the line, in pixels. Default value: 0. Minimum value: 0. The unit of lineBlur is in pixels.
getLineBorderColor() → Future<int?>
The color of the line border. If line-border-width is greater than zero and the alpha value of this color is 0 (default), the color for the border will be selected automatically based on the line color. Default value: "rgba(0, 0, 0, 0)".
getLineBorderWidth() → Future<double?>
The width of the line border. A value of zero means no border. Default value: 0. Minimum value: 0.
getLineCap() → Future<LineCap?>
The display of line endings. Default value: "butt".
getLineColor() → Future<int?>
The color with which the line will be drawn. Default value: "#000000".
getLineCrossSlope() → Future<double?>
Defines the slope of an elevated line. A value of 0 creates a horizontal line. A value of 1 creates a vertical line. Other values are currently not supported. If undefined, the line follows the terrain slope. This is an experimental property with some known issues: - Vertical lines don't support line caps - line-join: round is not supported with this property
getLineDasharray() → Future<List<double?>?>
Specifies the lengths of the alternating dashes and gaps that form the dash pattern. The lengths are later scaled by the line width. To convert a dash length to pixels, multiply the length by the current line width. Note that GeoJSON sources with lineMetrics: true specified won't render dashed lines to the expected scale. Also note that zoom-dependent expressions will be evaluated only at integer zoom levels. Minimum value: 0. The unit of lineDasharray is in line widths.
getLineDepthOcclusionFactor() → Future<double?>
Decrease line layer opacity based on occlusion from 3D objects. Value 0 disables occlusion, value 1 means fully occluded. Default value: 1. Value range: 0, 1
getLineElevationReference() → Future<LineElevationReference?>
Selects the base of line-elevation. Some modes might require precomputed elevation data in the tileset. Default value: "none".
getLineEmissiveStrength() → Future<double?>
Controls the intensity of light emitted on the source features. Default value: 0. Minimum value: 0. The unit of lineEmissiveStrength is in intensity.
getLineGapWidth() → Future<double?>
Draws a line casing outside of a line's actual path. Value indicates the width of the inner gap. Default value: 0. Minimum value: 0. The unit of lineGapWidth is in pixels.
getLineJoin() → Future<LineJoin?>
The display of lines when joining. Default value: "miter".
getLineMiterLimit() → Future<double?>
Used to automatically convert miter joins to bevel joins for sharp angles. Default value: 2.
getLineOcclusionOpacity() → Future<double?>
Opacity multiplier (multiplies line-opacity value) of the line part that is occluded by 3D objects. Value 0 hides occluded part, value 1 means the same opacity as non-occluded part. The property is not supported when line-opacity has data-driven styling. Default value: 0. Value range: 0, 1
getLineOffset() → Future<double?>
The line's offset. For linear features, a positive value offsets the line to the right, relative to the direction of the line, and a negative value to the left. For polygon features, a positive value results in an inset, and a negative value results in an outset. Default value: 0. The unit of lineOffset is in pixels.
getLineOpacity() → Future<double?>
The opacity at which the line will be drawn. Default value: 1. Value range: 0, 1
getLinePattern() → Future<String?>
Name of image in sprite to use for drawing image lines. For seamless patterns, image width must be a factor of two (2, 4, 8, ..., 512). Note that zoom-dependent expressions will be evaluated only at integer zoom levels.
getLineRoundLimit() → Future<double?>
Used to automatically convert round joins to miter joins for shallow angles. Default value: 1.05.
getLineSortKey() → Future<double?>
Sorts features in ascending order based on this value. Features with a higher sort key will appear above features with a lower sort key.
getLineTranslate() → Future<List<double?>?>
The geometry's offset. Values are x, y where negatives indicate left and up, respectively. Default value: 0,0. The unit of lineTranslate is in pixels.
getLineTranslateAnchor() → Future<LineTranslateAnchor?>
Controls the frame of reference for line-translate. Default value: "map".
getLineTrimColor() → Future<int?>
The color to be used for rendering the trimmed line section that is defined by the line-trim-offset property. Default value: "transparent".
getLineTrimFadeRange() → Future<List<double?>?>
The fade range for the trim-start and trim-end points is defined by the line-trim-offset property. The first element of the array represents the fade range from the trim-start point toward the end of the line, while the second element defines the fade range from the trim-end point toward the beginning of the line. The fade result is achieved by interpolating between line-trim-color and the color specified by the line-color or the line-gradient property. Default value: 0,0. Minimum value: 0,0. Maximum value: 1,1.
getLineTrimOffset() → Future<List<double?>?>
The line part between trim-start, trim-end will be painted using line-trim-color, which is transparent by default to produce a route vanishing effect. The line trim-off offset is based on the whole line range 0.0, 1.0. Default value: 0,0. Minimum value: 0,0. Maximum value: 1,1.
getLineWidth() → Future<double?>
Stroke thickness. Default value: 1. Minimum value: 0. The unit of lineWidth is in pixels.
getLineWidthUnit() → Future<LineWidthUnit?>
Selects the unit of line-width. The same unit is automatically used for line-blur and line-offset. Note: This is an experimental property and might be removed in a future release. Default value: "pixels".
getLineZOffset() → Future<double?>
Vertical offset from ground, in meters. Defaults to 0. This is an experimental property with some known issues: - Not supported for globe projection at the moment - Elevated line discontinuity is possible on tile borders with terrain enabled - Rendering artifacts can happen near line joins and line caps depending on the line styling - Rendering artifacts relating to line-opacity and line-blur - Elevated line visibility is determined by layer order - Z-fighting issues can happen with intersecting elevated lines - Elevated lines don't cast shadows Default value: 0.
longPressEvents({required dynamic onLongPress(PolylineAnnotation)}) → Cancelable
Registers long press event callbacks for the annotations managed by this manager.
noSuchMethod(Invocation invocation) → dynamic
Invoked when a nonexistent method or property is accessed.
inherited
setLineBlur(double lineBlur) → Future<void>
Blur applied to the line, in pixels. Default value: 0. Minimum value: 0. The unit of lineBlur is in pixels.
setLineBorderColor(int lineBorderColor) → Future<void>
The color of the line border. If line-border-width is greater than zero and the alpha value of this color is 0 (default), the color for the border will be selected automatically based on the line color. Default value: "rgba(0, 0, 0, 0)".
setLineBorderWidth(double lineBorderWidth) → Future<void>
The width of the line border. A value of zero means no border. Default value: 0. Minimum value: 0.
setLineCap(LineCap lineCap) → Future<void>
The display of line endings. Default value: "butt".
setLineColor(int lineColor) → Future<void>
The color with which the line will be drawn. Default value: "#000000".
setLineCrossSlope(double lineCrossSlope) → Future<void>
Defines the slope of an elevated line. A value of 0 creates a horizontal line. A value of 1 creates a vertical line. Other values are currently not supported. If undefined, the line follows the terrain slope. This is an experimental property with some known issues: - Vertical lines don't support line caps - line-join: round is not supported with this property
setLineDasharray(List<double?> lineDasharray) → Future<void>
Specifies the lengths of the alternating dashes and gaps that form the dash pattern. The lengths are later scaled by the line width. To convert a dash length to pixels, multiply the length by the current line width. Note that GeoJSON sources with lineMetrics: true specified won't render dashed lines to the expected scale. Also note that zoom-dependent expressions will be evaluated only at integer zoom levels. Minimum value: 0. The unit of lineDasharray is in line widths.
setLineDepthOcclusionFactor(double lineDepthOcclusionFactor) → Future<void>
Decrease line layer opacity based on occlusion from 3D objects. Value 0 disables occlusion, value 1 means fully occluded. Default value: 1. Value range: 0, 1
setLineElevationReference(LineElevationReference lineElevationReference) → Future<void>
Selects the base of line-elevation. Some modes might require precomputed elevation data in the tileset. Default value: "none".
setLineEmissiveStrength(double lineEmissiveStrength) → Future<void>
Controls the intensity of light emitted on the source features. Default value: 0. Minimum value: 0. The unit of lineEmissiveStrength is in intensity.
setLineGapWidth(double lineGapWidth) → Future<void>
Draws a line casing outside of a line's actual path. Value indicates the width of the inner gap. Default value: 0. Minimum value: 0. The unit of lineGapWidth is in pixels.
setLineJoin(LineJoin lineJoin) → Future<void>
The display of lines when joining. Default value: "miter".
setLineMiterLimit(double lineMiterLimit) → Future<void>
Used to automatically convert miter joins to bevel joins for sharp angles. Default value: 2.
setLineOcclusionOpacity(double lineOcclusionOpacity) → Future<void>
Opacity multiplier (multiplies line-opacity value) of the line part that is occluded by 3D objects. Value 0 hides occluded part, value 1 means the same opacity as non-occluded part. The property is not supported when line-opacity has data-driven styling. Default value: 0. Value range: 0, 1
setLineOffset(double lineOffset) → Future<void>
The line's offset. For linear features, a positive value offsets the line to the right, relative to the direction of the line, and a negative value to the left. For polygon features, a positive value results in an inset, and a negative value results in an outset. Default value: 0. The unit of lineOffset is in pixels.
setLineOpacity(double lineOpacity) → Future<void>
The opacity at which the line will be drawn. Default value: 1. Value range: 0, 1
setLinePattern(String linePattern) → Future<void>
Name of image in sprite to use for drawing image lines. For seamless patterns, image width must be a factor of two (2, 4, 8, ..., 512). Note that zoom-dependent expressions will be evaluated only at integer zoom levels.
setLineRoundLimit(double lineRoundLimit) → Future<void>
Used to automatically convert round joins to miter joins for shallow angles. Default value: 1.05.
setLineSortKey(double lineSortKey) → Future<void>
Sorts features in ascending order based on this value. Features with a higher sort key will appear above features with a lower sort key.
setLineTranslate(List<double?> lineTranslate) → Future<void>
The geometry's offset. Values are x, y where negatives indicate left and up, respectively. Default value: 0,0. The unit of lineTranslate is in pixels.
setLineTranslateAnchor(LineTranslateAnchor lineTranslateAnchor) → Future<void>
Controls the frame of reference for line-translate. Default value: "map".
setLineTrimColor(int lineTrimColor) → Future<void>
The color to be used for rendering the trimmed line section that is defined by the line-trim-offset property. Default value: "transparent".
setLineTrimFadeRange(List<double?> lineTrimFadeRange) → Future<void>
The fade range for the trim-start and trim-end points is defined by the line-trim-offset property. The first element of the array represents the fade range from the trim-start point toward the end of the line, while the second element defines the fade range from the trim-end point toward the beginning of the line. The fade result is achieved by interpolating between line-trim-color and the color specified by the line-color or the line-gradient property. Default value: 0,0. Minimum value: 0,0. Maximum value: 1,1.
setLineTrimOffset(List<double?> lineTrimOffset) → Future<void>
The line part between trim-start, trim-end will be painted using line-trim-color, which is transparent by default to produce a route vanishing effect. The line trim-off offset is based on the whole line range 0.0, 1.0. Default value: 0,0. Minimum value: 0,0. Maximum value: 1,1.
setLineWidth(double lineWidth) → Future<void>
Stroke thickness. Default value: 1. Minimum value: 0. The unit of lineWidth is in pixels.
setLineWidthUnit(LineWidthUnit lineWidthUnit) → Future<void>
Selects the unit of line-width. The same unit is automatically used for line-blur and line-offset. Note: This is an experimental property and might be removed in a future release. Default value: "pixels".
setLineZOffset(double lineZOffset) → Future<void>
Vertical offset from ground, in meters. Defaults to 0. This is an experimental property with some known issues: - Not supported for globe projection at the moment - Elevated line discontinuity is possible on tile borders with terrain enabled - Rendering artifacts can happen near line joins and line caps depending on the line styling - Rendering artifacts relating to line-opacity and line-blur - Elevated line visibility is determined by layer order - Z-fighting issues can happen with intersecting elevated lines - Elevated lines don't cast shadows Default value: 0.
tapEvents({required dynamic onTap(PolylineAnnotation)}) → Cancelable
Registers tap event callbacks for the annotations managed by this manager.
toString() → String
A string representation of this object.
inherited
update(PolylineAnnotation annotation) → Future<void>
Update an added annotation with new properties.