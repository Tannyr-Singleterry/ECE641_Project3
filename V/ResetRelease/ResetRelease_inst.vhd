	component ResetRelease is
		port (
			ninit_done : out std_logic   -- ninit_done
		);
	end component ResetRelease;

	u0 : component ResetRelease
		port map (
			ninit_done => CONNECTED_TO_ninit_done  -- ninit_done.ninit_done
		);

