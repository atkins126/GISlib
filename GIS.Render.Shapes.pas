unit GIS.Render.Shapes;

////////////////////////////////////////////////////////////////////////////////
//
// Author: Jaap Baak
// https://github.com/transportmodelling/GISlib
//
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
interface
////////////////////////////////////////////////////////////////////////////////

Uses
  Types,Graphics,Generics.Defaults,Generics.Collections,GIS,GIS.Shapes,
  GIS.Shapes.Polygon,GIS.Shapes.Polygon.PolyLabel,GIS.Render.Shapes.PixelConv;

Type
  TPointRenderStyle = (rsCircle,rsSquare,rsTriangleDown,rsTriangleUp,rsBitmap);

  TCustomShapesLayer = Class
  private
    FPointRenderSize: Integer;
    FPointRenderStyle: TPointRenderStyle;
    FPointBitmap: TBitmap;
    PolygonBitmap,PolygonBackgroundBitmap: TBitmap;
    Viewport: TCoordinateRect;
    Function GetBoundingBoxes(Shape: Integer): TCoordinateRect;
    Procedure InitPointRenderStyle;
    Procedure SetPointRenderStyle(PointRenderStyle: TPointRenderStyle);
    Procedure SetPointBitmap(PointBitmap: TBitmap);
    Procedure PointBitmapChange(Sender: TObject);
  strict protected
    Type
      TShapeRenderer = Class
      public
        Function Shape: TGISShape; virtual; abstract;
        Function BoundingBox: TCoordinateRect; virtual; abstract;
        Procedure Draw(const ShapeLabel: String;
                       const Canvas: TCanvas;
                       const PixelConverter: TCustomPixelConverter); virtual; abstract;
      end;
      TPointsRenderer = Class(TShapeRenderer)
      public
        Points: TShapePart;
        Layer: TCustomShapesLayer;
        Function Shape: TGISShape; override;
        Function BoundingBox: TCoordinateRect; override;
        Procedure Draw(const ShapeLabel: String;
                       const Canvas: TCanvas;
                       const PixelConverter: TCustomPixelConverter); override;
      end;
      TLinesRenderer = Class(TShapeRenderer)
      public
        Lines: TGISShape;
        Function Shape: TGISShape; override;
        Function BoundingBox: TCoordinateRect; override;
        Procedure Draw(const ShapeLabel: String;
                       const Canvas: TCanvas;
                       const PixelConverter: TCustomPixelConverter); override;
      end;
      TPolyPolygonsRenderer = Class(TShapeRenderer)
      private
        Type
          TLabelCoord = record
            Calculated: Boolean;
            Coordinate: TCoordinate;
          end;
        Var
          LabelCoords: array of TLabelCoord;
      public
        PolyPolygons: TPolyPolygons;
        ShapeBoundingBox: TCoordinateRect;
        Layer: TCustomShapesLayer;
        Function Shape: TGISShape; override;
        Function BoundingBox: TCoordinateRect; override;
        Procedure Draw(const ShapeLabel: String;
                       const Canvas: TCanvas;
                       const PixelConverter: TCustomPixelConverter); override;
      end;
    Const
      MaxPolyLabelIter = 100;
    Var
      FCount: Integer;
      FBoundingBox: TCoordinateRect;
    Function ShapeLabel(const Shape: Integer): String; virtual;
    Function ShapeRenderer(const Shape: Integer): TCustomShapesLayer.TShapeRenderer; virtual; abstract;
    Procedure SetPaintStyle(const Shape: Integer; const Canvas: TCanvas); virtual;
  public
    Constructor Create(const TransparentColor: TColor);
    Procedure DrawLayer(const Canvas: TCanvas;
                        const PixelConverter: TCustomPixelConverter;
                        const Width,Height: Integer); overload;
    Procedure DrawLayer(const Bitmap: TBitmap; const PixelConverter: TCustomPixelConverter); overload;
    Destructor Destroy; override;
  public
    Property BoundingBox: TCoordinateRect read FBoundingBox;
    Property BoundingBoxes[Shape: Integer]: TCoordinateRect read GetBoundingBoxes;
  end;

  TShapesLayer = Class(TCustomShapesLayer)
  private
    FShapeCount: array[TShapeType] of Integer;
    ShapeRenderers: array of TCustomShapesLayer.TShapeRenderer;
    Procedure EnsureCapacity;
    Function GetShapes(Shape: Integer): TGISShape;
  strict protected
    Function ShapeRenderer(const Shape: Integer): TCustomShapesLayer.TShapeRenderer; override;
  public
    Constructor Create(const TransparentColor: TColor; InitialCapacity: Integer = 256);
    Procedure Clear;
    Procedure Add(Shape: TGISShape);
    Function ShapeCount(ShapeType: TShapeType): Integer;
    Procedure Read(const FileName: String; const FileFormat: TShapesFormat);
    Destructor Destroy; override;
  public
    Property Count: Integer read FCount;
    Property Shapes[Shape: Integer]: TGISShape read GetShapes; default;
    Property PointRenderSize: Integer read FPointRenderSize write FPointRenderSize;
    Property PointRenderStyle: TPointRenderStyle read FPointRenderStyle write SetPointRenderStyle;
    Property PointBitmap: TBitmap read FPointBitmap write SetPointBitmap;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Function TCustomShapesLayer.TPointsRenderer.Shape: TGISShape;
begin
  Result.AssignPoints(Points);
end;

Function TCustomShapesLayer.TPointsRenderer.BoundingBox: TCoordinateRect;
begin
   Result := Points.BoundingBox;
end;

Procedure TCustomShapesLayer.TPointsRenderer.Draw(const ShapeLabel: String;
                                                  const Canvas: TCanvas;
                                                  const PixelConverter: TCustomPixelConverter);
begin
  var PointsCount := Points.Count;
  var Radius := Layer.FPointRenderSize div 2;
  for var Point := 0 to PointsCount-1 do
  begin
    var Pixel := PixelConverter.CoordToPixel(Points[Point]);
    case Layer.FPointRenderStyle of
      rsCircle: Canvas.Ellipse(Pixel.X-Radius,Pixel.Y-Radius,Pixel.X+Radius,Pixel.Y+Radius);
      rsSquare: Canvas.Rectangle(Pixel.X-Radius,Pixel.Y-Radius,Pixel.X+Radius,Pixel.Y+Radius);
      rsTriangleUp: Canvas.Polygon([Types.Point(Pixel.X-Radius,Pixel.Y+Radius),
                                    Types.Point(Pixel.X+Radius,Pixel.Y+Radius),
                                    Types.Point(Pixel.X,Pixel.Y-Radius)]);
      rsTriangleDown: Canvas.Polygon([Types.Point(Pixel.X-Radius,Pixel.Y-Radius),
                                      Types.Point(Pixel.X+Radius,Pixel.Y-Radius),
                                      Types.Point(Pixel.X,Pixel.Y+Radius)]);
      rsBitmap:
        begin
          var X := Pixel.X - (Layer.FPointBitmap.Width div 2);
          var Y := Pixel.Y - (Layer.FPointBitmap.Height div 2);
          Canvas.Draw(X,Y,Layer.FPointBitmap);
        end;
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Function TCustomShapesLayer.TLinesRenderer.Shape: TGISShape;
begin
  Result := Lines;
end;

Function TCustomShapesLayer.TLinesRenderer.BoundingBox: TCoordinateRect;
begin
   Result := Lines.BoundingBox;
end;

Procedure TCustomShapesLayer.TLinesRenderer.Draw(const ShapeLabel: String;
                                                 const Canvas: TCanvas;
                                                 const PixelConverter: TCustomPixelConverter);
begin
  for var Part := 0 to Lines.Count-1 do
  begin
    var PointsCount := Lines.Parts[Part].Count;
    var Pixel := PixelConverter.CoordToPixel(Lines[Part,0]);
    Canvas.MoveTo(Pixel.X,Pixel.Y);
    for var Point := 1 to PointsCount-1 do
    begin
      Pixel := PixelConverter.CoordToPixel(Lines[Part,Point]);
      Canvas.LineTo(Pixel.X,Pixel.Y);
    end;
  end;
end;

////////////////////////////////////////////////////////////////////////////////

Function TCustomShapesLayer.TPolyPolygonsRenderer.Shape: TGISShape;
Var
  Parts: array of TShapePart;
begin
  for var Outer := 0 to PolyPolygons.Count-1 do
  begin
    Parts := Parts + [PolyPolygons[Outer].OuterRing];
    for var Hole := 0 to PolyPolygons[Outer].HolesCount-1 do
    Parts := Parts + [PolyPolygons[Outer].Holes[Hole]];
  end;
  Result.AssignPolyPolygon(Parts);
end;

Function TCustomShapesLayer.TPolyPolygonsRenderer.BoundingBox: TCoordinateRect;
begin
   Result := ShapeBoundingBox;
end;

Procedure TCustomShapesLayer.TPolyPolygonsRenderer.Draw(const ShapeLabel: String;
                                                        const Canvas: TCanvas;
                                                        const PixelConverter: TCustomPixelConverter);
Var
  LabelCoord: TCoordinate;
  Pixels: array of TPoint;
begin
  var PolygonBitmap := Layer.PolygonBitmap;
  var PolygonBackgroundBitmap := Layer.PolygonBackgroundBitmap;
  // Clear polygon bitmap
  PolygonBitmap.Canvas.Draw(0,0,PolygonBackgroundBitmap);
  // Draw poly polygons on polygon bitmap
  for var Outer := 0 to PolyPolygons.Count-1 do
  begin
    var PolyPolygon := PolyPolygons[Outer];
    // Calculate pixels outer ring
    var OuterRing := PolyPolygon.OuterRing;
    SetLength(Pixels,OuterRing.Count);
    for var Point := 0 to OuterRing.Count-1 do
    Pixels[Point] := PixelConverter.CoordToPixel(OuterRing[Point]);
    // Draw outer ring
    var PixelBoundingBox := TRect.Union(Pixels);
    if (PixelBoundingBox.Width > 0) and (PixelBoundingBox.Height > 0) then
    begin
      PolygonBitmap.Canvas.Brush := Canvas.Brush;
      PolygonBitmap.Canvas.Polygon(Pixels);
      // Draw label
      var LabelSize := PolygonBitmap.Canvas.TextExtent(ShapeLabel);
      if (PixelBoundingBox.Width > 1.75*LabelSize.cx)
      and (PixelBoundingBox.Height > 1.75*LabelSize.cy) then
      begin
        if LabelCoords[Outer].Calculated then
          LabelCoord := LabelCoords[Outer].Coordinate
        else
          begin
            LabelCoord := TPolyLabel.PolyLabel(PolyPolygon,MaxPolyLabelIter);
            LabelCoords[Outer].Calculated := true;
            LabelCoords[Outer].Coordinate := LabelCoord;
          end;
        var LabelPixel := PixelConverter.CoordToPixel(LabelCoord);
        var X := LabelPixel.X - (LabelSize.cx div 2);
        var Y := LabelPixel.Y - (LabelSize.cy div 2);
        PolygonBitmap.Canvas.TextOut(X,Y,ShapeLabel);
      end;
      // Draw holes
      for var Inner := 0 to PolyPolygon.HolesCount-1 do
      begin
        // Calculate pixels hole
        var Hole := PolyPolygon.Holes[Inner];
        SetLength(Pixels,Hole.Count);
        for var Point := 0 to Hole.Count-1 do
        Pixels[Point] := PixelConverter.CoordToPixel(Hole[Point]);
        // Draw hole
        PolygonBitmap.Canvas.Brush.Style := bsSolid;
        PolygonBitmap.Canvas.Brush.Color := PolygonBitmap.TransparentColor;
        PolygonBitmap.Canvas.Polygon(Pixels);
      end;
    end;
  end;
  // Draw polygon bitmap
  Canvas.Draw(0,0,PolygonBitmap);
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TCustomShapesLayer.Create(const TransparentColor: TColor);
// TransparentColor designates an unused color to be used for polygon rendering
begin
  inherited Create;
  FBoundingBox.Clear;
  FPointBitmap := TBitmap.Create;
  FPointBitmap.OnChange := PointBitmapChange;
  PolygonBitmap := TBitmap.Create;
  PolygonBitmap.Transparent := true;
  PolygonBitmap.TransparentColor := TransparentColor;
  PolygonBackgroundBitmap := TBitmap.Create;
  PolygonBackgroundBitmap.Canvas.Brush.Style := bsSolid;
  PolygonBackgroundBitmap.Canvas.Brush.Color := TransparentColor;
  InitPointRenderStyle;
end;

Function TCustomShapesLayer.GetBoundingBoxes(Shape: Integer): TCoordinateRect;
begin
  Result := ShapeRenderer(Shape).BoundingBox;
end;

Procedure TCustomShapesLayer.InitPointRenderStyle;
begin
  FPointRenderStyle := rsCircle;
  FPointRenderSize := 6;
end;

Procedure TCustomShapesLayer.SetPointRenderStyle(PointRenderStyle: TPointRenderStyle);
begin
  if (PointRenderStyle <> rsBitmap) or (not FPointBitmap.Empty) then FPointRenderStyle := PointRenderStyle;
end;

Procedure TCustomShapesLayer.SetPointBitmap(PointBitmap: TBitmap);
begin
  FPointBitmap.Assign(PointBitmap);
end;

Procedure TCustomShapesLayer.PointBitmapChange(sender: TObject);
begin
  if (FPointRenderStyle = rsBitmap) and FPointBitmap.Empty then InitPointRenderStyle;
end;

Function TCustomShapesLayer.ShapeLabel(const Shape: Integer): String;
begin
  Result := '';
end;

Procedure TCustomShapesLayer.SetPaintStyle(const Shape: Integer; const Canvas: TCanvas);
begin
end;

Procedure TCustomShapesLayer.DrawLayer(const Canvas: TCanvas;
                                       const PixelConverter: TCustomPixelConverter;
                                       const Width,Height: Integer);
begin
  Viewport := PixelConverter.PixelToCoord(Width,Height);
  PolygonBitmap.SetSize(Width,Height);
  PolygonBitmap.Canvas.Pen := Canvas.Pen;
  PolygonBackgroundBitmap.SetSize(Width,Height);
  PolygonBackgroundBitmap.Canvas.FillRect(Rect(0,0,Width,Height));
  for var Shape := 0 to FCount-1 do
  begin
    var ShpRenderer := ShapeRenderer(Shape);
    if Viewport.IntersectsWith(ShpRenderer.BoundingBox) then
    begin
      var ShpLabel := ShapeLabel(Shape);
      SetPaintStyle(Shape,Canvas);
      ShpRenderer.Draw(ShpLabel,Canvas,PixelConverter);
    end;
  end;
end;

Procedure TCustomShapesLayer.DrawLayer(const Bitmap: TBitmap; const PixelConverter: TCustomPixelConverter);
begin
  DrawLayer(Bitmap.Canvas,PixelConverter,Bitmap.Width,Bitmap.Height);
end;

Destructor TCustomShapesLayer.Destroy;
begin
  FPointBitmap.Free;
  PolygonBitmap.Free;
  PolygonBackgroundBitmap.Free;
  inherited Destroy;
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TShapesLayer.Create(const TransparentColor: TColor; InitialCapacity: Integer = 256);
begin
  inherited Create(TransparentColor);
  SetLength(ShapeRenderers,InitialCapacity);
end;

Procedure TShapesLayer.EnsureCapacity;
begin
  if FCount = Length(ShapeRenderers) then
  begin
    var Delta := Round(0.25*FCount);
    if Delta < 256 then Delta := 256;
    SetLength(ShapeRenderers,FCount+Delta);
  end;
end;

Function TShapesLayer.GetShapes(Shape: Integer): TGISShape;
begin
  Result := ShapeRenderers[Shape].Shape;
end;

Function TShapesLayer.ShapeRenderer(const Shape: Integer): TCustomShapesLayer.TShapeRenderer;
begin
  Result := ShapeRenderers[Shape];
end;

Procedure TShapesLayer.Clear;
begin
  FCount := 0;
  for var ShapeType := low(TShapeType) to high(TShapeType) do FShapeCount[ShapeType] := 0;
  FBoundingBox.Clear;
end;

Procedure TShapesLayer.Add(Shape: TGISShape);
begin
  EnsureCapacity;
  case Shape.ShapeType of
    stPoint:
      begin
        var Renderer := TCustomShapesLayer.TPointsRenderer.Create;
        Renderer.Points := Shape.Parts[0];
        Renderer.Layer := Self;
        ShapeRenderers[FCount] := Renderer;
      end;
    stLine:
      begin
        var Renderer := TCustomShapesLayer.TLinesRenderer.Create;
        Renderer.Lines := Shape;
        ShapeRenderers[FCount] := Renderer;
      end;
    stPolygon:
      begin
        var Renderer := TCustomShapesLayer.TPolyPolygonsRenderer.Create;
        Renderer.PolyPolygons := TPolyPolygons.Create(Shape);
        Renderer.ShapeBoundingBox := Shape.BoundingBox;
        Renderer.Layer := Self;
        SetLength(Renderer.LabelCoords,Renderer.PolyPolygons.Count);
        ShapeRenderers[FCount] := Renderer;
      end;
  end;
  Inc(FCount);
  Inc(FShapeCount[Shape.ShapeType]);
  FBoundingBox.Enclose(Shape.BoundingBox);
end;

Function TShapesLayer.ShapeCount(ShapeType: TShapeType): Integer;
begin
  Result := FShapeCount[ShapeType];
end;

Procedure TShapesLayer.Read(const FileName: String; const FileFormat: TShapesFormat);
Var
  Shape: TGISShape;
begin
  var Reader := FileFormat.Create(FileName);
  try
    while Reader.ReadShape(Shape) do Add(Shape);
  finally
    Reader.Free;
  end;
end;

Destructor TShapesLayer.Destroy;
begin
  for var Renderer := low(ShapeRenderers) to high(ShapeRenderers) do ShapeRenderers[Renderer].Free;
  inherited Destroy;
end;

end.
