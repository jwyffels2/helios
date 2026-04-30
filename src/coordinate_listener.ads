package Coordinate_Listener is

   type Coordinate is record
      Latitude  : Float;
      Longitude : Float;
   end record;

   procedure Init;

   procedure Poll;

   function Get_Coordinates return Coordinate;

end Coordinate_Listener;
