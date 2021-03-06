unit GIS.Shapes.Polygon;

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
  SysUtils,Types,Math,Generics.Defaults,Generics.Collections,GIS,GIS.Shapes;

Type
  TPointLocation = (plInterior,plExterior,plHole);

  TPolyPolygon = record
  private
    Class Function RingArea(const Points: array of TCoordinate): Float64; static;
    Class Function LineSegmentsIntersect(const A,B,P,Q: TCoordinate): Boolean; static;
    Class Function NrIntersections(const [ref] Point: TCoordinate; const [ref] Ring: TShapePart): Integer; static;
    Class Function PointInRing(const [ref] Point: TCoordinate; const [ref] Ring: TShapePart): Boolean; static;
  private
    FOuterRing: TShapePart;
    FHoles: array of TShapePart;
    Function GetHoles(Hole: Integer): TShapePart; inline;
    Function DistanceToLineSegment(const [ref] Point,A,B: TCoordinate): Float64;
    Function DistanceToRing(const [ref] Point: TCoordinate; const [ref] Ring: TShapePart): Float64;
  public
    Function HolesCount: Integer;
    Function PointLocation(const [ref] Point: TCoordinate; out Hole: Integer): TPointLocation;
    Function Distance(const [ref] Point: TCoordinate; out Location: TPointLocation): Float64;
  public
    Property OuterRing: TShapePart read FOuterRing;
    Property Holes[Hole: Integer]: TShapePart read GetHoles;
  end;

  TPolyPolygons = record
  private
    FPolyPolygons: array of TPolyPolygon;
    Function GetPolyPolygons(Polypolygon: Integer): TPolyPolygon;
  public
    Constructor Create(const [ref] PolyPolygons: TGISShape);
    Function Count: Integer;
  public
    Property PolyPolygons[PolyPolygon: Integer]: TPolyPolygon read GetPolyPolygons; default;
  end;

////////////////////////////////////////////////////////////////////////////////
implementation
////////////////////////////////////////////////////////////////////////////////

Function TPolyPolygon.GetHoles(Hole: Integer): TShapePart;
begin
  Result := FHoles[Hole];
end;

Class Function TPolyPolygon.RingArea(const Points: array of TCoordinate): Float64;
var
  BoundingBox: TCoordinateRect;
begin
  // Calculate ring center, so the ring can be moved to the origin for numerical stability
  BoundingBox.Clear;
  BoundingBox.Enclose(Points);
  var Center := BoundingBox.CenterPoint;
  var X0 := Center.X;
  var Y0 := Center.Y;
  // Calculate area
  Result := 0.0;
  for var Point := low(Points) to pred(high(Points)) do
  Result := Result + (Points[Point].X-X0)*(Points[Point+1].Y-Y0)
                   - (Points[Point+1].X-X0)*(Points[Point].Y-Y0);
end;

Class Function TPolyPolygon.LineSegmentsIntersect(const A,B,P,Q: TCoordinate): Boolean;
// Tests whether line segments AB and PQ intersect
// (does not handle the case where AB and PQ are collinear)
begin
  if RingArea([A,B,P])*RingArea([A,B,Q]) < 0.0 then
    if RingArea([P,Q,A])*RingArea([P,Q,B]) < 0.0 then
      Result := true
    else
      Result := false
  else
    Result := false;
end;

Class Function TPolyPolygon.NrIntersections(const [ref] Point: TCoordinate;
                                            const [ref] Ring: TShapePart): Integer;
// Returns the number of intersection between Ring
// and the line from Point to Point(infinity,Point.Y).
Const
  Below = -1;
  Above = +1;
begin
  Result := 0;
  if Ring.Count > 0 then
  begin
    // Find a vertex that is either above or below Point
    var First := 0;
    var Position := 0;
    repeat
      if Ring[First].Y < Point.Y then Position := Below else
      if Ring[First].Y > Point.Y then Position := Above else
      Inc(First);
    until (Position <> 0) or (First = Ring.Count);
   // Test whether edges intersect the line from Point to Point(infinite,Point.Y)
    if First < Ring.Count then
    begin
      var Previous := First;
      var TestPoint := TCoordinate.Create(Ring.BoundingBox.Right+Ring.BoundingBox.Width,Point.Y);
      for var Vertex := 1 to Ring.Count do
      begin
        var Current := (First+Vertex) mod Ring.Count;
        if (Position = Above) and (Ring[Current].Y < Point.Y) then
        begin
          Position := Below;
          if (Ring[Current].X > Point.X) and (Ring[Previous].X > Point.X) then Inc(Result) else
          if (Ring[Current].X > Point.X) or (Ring[Previous].X > Point.X) then
          if LineSegmentsIntersect(Point,TestPoint,Ring.Points[Previous],Ring.Points[Current]) then Inc(Result)
        end else
        if (Position = Below) and (Ring[Current].Y > Point.Y) then
        begin
          Position := Above;
          if (Ring[Current].X > Point.X) and (Ring[Previous].X > Point.X) then Inc(Result) else
          if (Ring[Current].X > Point.X) or (Ring[Previous].X > Point.X) then
          if LineSegmentsIntersect(Point,TestPoint,Ring.Points[Previous],Ring.Points[Current]) then Inc(Result)
        end;
        Previous := Current;
      end;
    end;
  end;
end;

Class Function TPolyPolygon.PointInRing(const [ref] Point: TCoordinate;
                                  const [ref] Ring: TShapePart): Boolean;
begin
  Result := ((NrIntersections(Point,Ring) mod 2) = 1);
end;

Function TPolyPolygon.DistanceToLineSegment(const [ref] Point,A,B: TCoordinate): Float64;
begin
  var SqrAB := TCoordinate.SqrDistance(A,B);
  if SqrAB <> 0 then
  begin
    var u := ( (Point.X-A.X)*(B.X-A.X) + (Point.Y-A.Y)*(B.Y-A.Y) ) / SqrAB;
    if u < 0 then Result := TCoordinate.Distance(A,Point) else
    if u > 1 then Result := TCoordinate.Distance(B,Point) else
    begin
      var P := TCoordinate.Create( (1-u)*A.X+u*B.X ,(1-u)*A.Y+u*B.Y );
      Result := TCoordinate.Distance(P,Point);
    end
  end else
    // Points A and B coincide
    Result := TCoordinate.Distance(A,Point);
end;

Function TPolyPolygon.DistanceToRing(const [ref] Point: TCoordinate; const [ref] Ring: TShapePart): Float64;
begin
  Result := Infinity;
  for var Segment := 1 to Ring.Count-1 do
  begin
    var Dist := DistanceToLineSegment(Point,Ring.Points[Segment-1],Ring.Points[Segment]);
    if Dist < Result then Result := Dist;
  end;
end;

Function TPolyPolygon.PointLocation(const [ref] Point: TCoordinate; out Hole: Integer): TPointLocation;
begin
  Hole := -1;
  if PointInRing(Point,FOuterRing) then
  begin
    Result := plInterior;
    for var Index := low(FHoles) to high(FHoles) do
    if PointInRing(Point,FHoles[Index]) then
    begin
      Result := plHole;
      Hole := Index;
    end
  end else
    Result := plExterior;
end;

Function TPolyPolygon.Distance(const [ref] Point: TCoordinate;
                               out Location: TPointLocation): Float64;
Var
  Hole: Integer;
begin
  Location := PointLocation(Point,Hole);
  case Location of
    plExterior:
      Result := DistanceToRing(Point,FOuterRing);
    plHole:
      Result := DistanceToRing(Point,FHoles[Hole]);
    plInterior:
      begin
        Result := DistanceToRing(Point,FOuterRing);
        for Hole := low(FHoles) to high(FHoles) do
        begin
          var DistanceToHole := DistanceToRing(Point,FHoles[Hole]);
          if DistanceToHole < Result then Result := DistanceToHole;
        end;
      end;
  end;
end;

Function TPolyPolygon.HolesCount: Integer;
begin
  Result := Length(FHoles);
end;

////////////////////////////////////////////////////////////////////////////////

Constructor TPolyPolygons.Create(const [ref] PolyPolygons: TGISShape);
Var
  BoundingBoxAreas: array of Float64;
  PolygonIndices,EnclosingPolygonsCount,LastEnclosingPolygon: array of Integer;
begin
  if PolyPolygons.ShapeType = stPolygon then
    if PolyPolygons.Count > 1 then
    begin
      // Calculate bounding box areas
      SetLength(BoundingBoxAreas,PolyPolygons.Count);
      for var Polygon := 0 to PolyPolygons.Count-1 do
      BoundingBoxAreas[Polygon] := PolyPolygons.Parts[Polygon].BoundingBox.Area;
      // Sort polygons (large bounding box area before small bounding box area)
      SetLength(PolygonIndices,PolyPolygons.Count);
      for var Polygon := 0 to PolyPolygons.Count-1 do PolygonIndices[Polygon] := Polygon;
      TArray.Sort<Integer>(PolygonIndices,TComparer<Integer>.Construct(
         Function(const Left,Right: Integer): Integer
         begin
           var LeftArea := Abs(BoundingBoxAreas[Left]);
           var RightArea := Abs(BoundingBoxAreas[Right]);
           if LeftArea > RightArea then Result := -1 else
           if LeftArea < RightArea then Result := +1 else
           Result := 0;
         end ),0,PolyPolygons.Count);
      // Count number of enclosing polygons
      SetLength(EnclosingPolygonsCount,PolyPolygons.Count);
      SetLength(LastEnclosingPolygon,PolyPolygons.Count);
      LastEnclosingPolygon[0] := -1;
      for var Polygon := 1 to PolyPolygons.Count-1 do
      begin
        var PolygonIndex := PolygonIndices[Polygon];
        var PolygonBoundingBox := PolyPolygons.Parts[PolygonIndex].BoundingBox;
        // Find last enclosing polygon
        LastEnclosingPolygon[Polygon] := -1;
        for var PotentialEnclosingPolygon := Polygon-1 downto 0 do
        begin
          var EnclosingPolygonIndex := PolygonIndices[PotentialEnclosingPolygon];
          var EnclosingPolygonBoundingBox := PolyPolygons.Parts[EnclosingPolygonIndex].BoundingBox;
          if EnclosingPolygonBoundingBox.Contains(PolygonBoundingBox) then
          begin
            var TestPoint := PolyPolygons.Parts[PolygonIndex].Points[0];
            if TPolyPolygon.PointInRing(TestPoint,PolyPolygons.Parts[EnclosingPolygonIndex]) then
            begin
              EnclosingPolygonsCount[Polygon] := EnclosingPolygonsCount[PotentialEnclosingPolygon]+1;
              LastEnclosingPolygon[Polygon] := PotentialEnclosingPolygon;
              Break;
            end;
          end;
        end;
      end;
      // Select outer rings
      var OuterCount := 0;
      SetLength(FPolyPolygons,PolyPolygons.Count);
      for var Polygon := 0 to PolyPolygons.Count-1 do
      if EnclosingPolygonsCount[Polygon] mod 2 = 0 then
      begin
        var PolygonIndex := PolygonIndices[Polygon];
        var OuterRing := PolyPolygons.Parts[PolygonIndex];
        FPolyPolygons[OuterCount].FOuterRing := OuterRing;
        // Select holes
        for var PotentialHole := Polygon+1 to PolyPolygons.Count-1 do
        if LastEnclosingPolygon[PotentialHole] = Polygon then
        begin
          var HoleIndex := PolygonIndices[PotentialHole];
          var Hole := PolyPolygons.Parts[HoleIndex];
          FPolyPolygons[OuterCount].FHoles := FPolyPolygons[OuterCount].FHoles + [Hole];
        end;
        Inc(OuterCount);
      end;
      SetLength(FPolyPolygons,OuterCount);
    end else
    begin
      SetLength(FPolyPolygons,1);
      FPolyPolygons[0].FOuterRing := PolyPolygons.Parts[0];
    end
  else
    raise Exception.Create('Invalid shape type');
end;

Function TPolyPolygons.GetPolyPolygons(Polypolygon: Integer): TPolyPolygon;
begin
  Result := FPolyPolygons[PolyPolygon];
end;

Function TPolyPolygons.Count: Integer;
begin
  Result := Length(FPolyPolygons);
end;

end.
