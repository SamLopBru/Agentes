model Wumpus_template

global {
    int total_gold_collected <- 0;
    int deaths_by_pit <- 0;
    int deaths_by_wumpus <- 0;
    bool game_over <- false;
    bool player_won <- false;
    int steps_taken <- 0;
    int gold_to_win <- 3;
    int num_pits <- 2;
    int num_wumpus <- 1;
    int num_gold <- 1;
    int grid_size <- 25;
    bool is_batch <- false;
    graph world_graph;
    
	
    
  
    // Difficulty level (set by experiment parameters)
    string difficulty <- "Easy";
    point initial_player_position <- nil;
    
    init {
        // Reset ALL variables at start of each simulation
        total_gold_collected <- 0;
        deaths_by_pit <- 0;
        deaths_by_wumpus <- 0;
        game_over <- false;
        player_won <- false;
        steps_taken <- 0;
        initial_player_position <- nil;
        world_graph <- as_edge_graph(gworld);
        
        create goldArea number: 1;
        create wumpusArea number: num_wumpus;
        create pitArea number: num_pits;
        create player number: 1;
    }
    
    reflex count_steps {
        steps_taken <- steps_taken + 1;
        
        // Individual simulation timeout
        if (steps_taken >= 5500 and !game_over) {
            write "Simulation timeout at " + steps_taken + " steps";
            game_over <- true;
            player_won <- false;
            ask player { do die; }
        }
    }
    

    // Save data when game ends
    reflex save_data when: game_over and !is_batch {
    save [
        difficulty,
        player_won ? "WIN" : "LOSS",
        total_gold_collected,
        steps_taken,
        deaths_by_pit,
        deaths_by_wumpus,
        num_pits,
        num_wumpus,
        initial_player_position != nil ? initial_player_position.x : 0,
        initial_player_position != nil ? initial_player_position.y : 0
    ] to: "test_cases_all.csv" rewrite: false format: 'csv';

    do pause;  // This pause only affects GUI mode now
}
}

grid gworld width: 25 height: 25 neighbors: 4 {
    rgb color <- #green;
}

species odorArea {
    aspect base {
        draw square(4) color: #brown border: #black;
    }
}

species wumpusArea {
    init {
        gworld place <- one_of(gworld);
        location <- place.location;

        list<gworld> my_neighbors <- [];
        ask place {
            my_neighbors <- neighbors;
        }

        loop i over: my_neighbors {
            create odorArea {
                location <- i.location;
            }
        }
    }
    
    aspect base {
        draw image("./images/wumpus.png") size: 5;
    }
}

species glitterArea {
    aspect base {
        draw square(4) color: #chartreuse border: #black;
    }
}

species goldArea {
    init {
        gworld place <- nil;
        
        // Find a cell not occupied by wumpus or pits
        loop while: place = nil {
            gworld candidate <- one_of(gworld);
            bool is_occupied <- false;
            
            ask wumpusArea {
                if (self.location = candidate.location) {
                    is_occupied <- true;
                }
            }
            
            ask pitArea {
                if (self.location = candidate.location) {
                    is_occupied <- true;
                }
            }
            
            if (!is_occupied) {
                place <- candidate;
            }
        }
        
        location <- place.location;

        list<gworld> my_neighbors <- [];
        ask place {
            my_neighbors <- neighbors;
        }

        loop i over: my_neighbors {
            create glitterArea {
                location <- i.location;
            }
        }
    }
    
    aspect base {
        draw image("./images/gold.png") size: 3;
    }
}

species breezeArea {
    aspect base {
        draw square(4) color: #lightblue border: #black;
    }
}

species pitArea {
    init {
        gworld place <- one_of(gworld);
        location <- place.location;
        
        list<gworld> my_neighbors <- [];
        ask place {
            my_neighbors <- neighbors;
        }
        
        loop i over: my_neighbors {
            create breezeArea {
                location <- i.location;
            }
        }
    }
    
    aspect base {
        draw square(4) color: #black border: #black;
    }
}

species player skills: [moving] control: simple_bdi {
    gworld my_cell;
    gworld previous_cell;
    
    // Predicates for beliefs
    predicate pit_detected <- new_predicate("pit_nearby");
    predicate wumpus_detected <- new_predicate("wumpus_nearby");
    predicate gold_detected <- new_predicate("gold_nearby");
    predicate safe_cell <- new_predicate("safe_location");
    predicate danger_detected <- new_predicate("danger");
    predicate exploring <- new_predicate("exploring");
    
    // Predicates for desires
    predicate patrol_desire <- new_predicate("patrol");
    predicate collect_gold_desire <- new_predicate("collect_gold");
    predicate avoid_wumpus_desire <- new_predicate("avoid_wumpus");
    predicate avoid_pit_desire <- new_predicate("avoid_pit");
    predicate escape_danger_desire <- new_predicate("escape_danger");
    predicate explore_desire <- new_predicate("explore");
    
    // Memory
    list<point> known_pit_locations <- [];
    list<point> known_wumpus_locations <- [];
    int max_memory_pits <- 10;
    list<point> known_gold_locations <- [];
    int max_memory_gold <- 5;
    
    // NEW: Visit tracking to prevent wandering in same area
    list<point> visited_locations <- [];
    int max_memory_visits <- 50;
    int stuck_counter <- 0;
    point last_location <- nil;
    
    // Target tracking
    point gold_target <- nil;
    point exploration_target <- nil;
    path current_path <- nil;
    
    bool is_alive <- true;
    int gold_collected <- 0;
    float speed <- 1.0;  // Reduced speed for better grid movement
    
    init {
        // Build list of safe starting cells manually
        list<gworld> safe_starts <- [];
        
        loop cell over: gworld {
            bool is_safe <- true;
            
            // Check if pit is too close
            ask pitArea {
                if (self.location distance_to cell.location < 5) {
                    is_safe <- false;
                }
            }
            
            // Check if wumpus is too close
            ask wumpusArea {
                if (self.location distance_to cell.location < 5) {
                    is_safe <- false;
                }
            }
            
            if (is_safe) {
                add cell to: safe_starts;
            }
        }
        
        // Choose starting position
        if (!empty(safe_starts)) {
            my_cell <- one_of(safe_starts);
        } else {
            my_cell <- one_of(gworld);
        }
        
        previous_cell <- my_cell;
        location <- my_cell.location;
        last_location <- location;
        
        // Store initial position
        initial_player_position <- location;
        add location to: visited_locations;
        
        write "Player starting at: " + location;
        
        // Set clear priority hierarchy
        do add_desire(explore_desire);
        do add_desire(collect_gold_desire);
        do add_desire(patrol_desire);
    }
    
    // Track if stuck in same area
    reflex check_stuck when: is_alive {
        if (last_location != nil and location distance_to last_location < 2.0) {
            stuck_counter <- stuck_counter + 1;
        } else {
            stuck_counter <- 0;
        }
        
        // Force exploration if stuck
        if (stuck_counter > 5) {
            write "Agent stuck! Forcing exploration...";
            exploration_target <- nil;
            gold_target <- nil;
            do remove_intention(patrol_desire, true);
            do add_desire(explore_desire);
            stuck_counter <- 0;
        }
        
        last_location <- location;
    }
    
    // PERCEPTIONS
    perceive target: breezeArea in: 1 {
        focus id: "breeze_detected" var: location strength: 8.0;
        ask myself {
            do add_belief(pit_detected);
            do add_belief(danger_detected);
            do add_desire(escape_danger_desire);
            
            if (!(myself.location in known_pit_locations)) {
                if (length(known_pit_locations) >= max_memory_pits) {
                    remove index: 0 from: known_pit_locations;
                }
                add myself.location to: known_pit_locations;
            }
        }
    }

    perceive target: odorArea in: 1 {
        focus id: "odor_detected" var: location strength: 9.0;
        ask myself {
            do add_belief(wumpus_detected);
            do add_belief(danger_detected);
            do add_desire(escape_danger_desire);
            
            if (!(myself.location in known_wumpus_locations)) {
                add myself.location to: known_wumpus_locations;
            }
        }
    }

    perceive target: glitterArea in: 5 {  // Increased perception range
        focus id: "glitter_detected" var: location strength: 10.0;
        ask myself {
            do add_belief(gold_detected);
            do add_desire(collect_gold_desire);
            
            // Find nearest gold and set as target
            list<goldArea> nearby_gold <- goldArea at_distance 10;
            if (!empty(nearby_gold)) {
                goldArea closest_gold <- nearby_gold closest_to self;
                gold_target <- closest_gold.location;
                
                if (length(known_gold_locations) >= max_memory_gold) {
                    remove index: 0 from: known_gold_locations;
                }
                if (!(gold_target in known_gold_locations)) {
                    add gold_target to: known_gold_locations;
                }
                
                write "Gold detected! Target set at: " + gold_target;
            }
        }
    }
    
    // RULES with clear strengths
    rule belief: pit_detected new_desire: escape_danger_desire strength: 10.0;
    rule belief: wumpus_detected new_desire: escape_danger_desire strength: 10.0;
    rule belief: danger_detected new_desire: escape_danger_desire strength: 10.0;
    rule belief: gold_detected new_desire: collect_gold_desire strength: 9.0;
    
    // PLAN 1: ESCAPE - Highest priority
    plan escape_plan intention: escape_danger_desire priority: 10 {
        if (previous_cell != nil and previous_cell != my_cell) {
            my_cell <- previous_cell;
            location <- my_cell.location;
            
            current_path <- nil;
            gold_target <- nil;
            
            if (has_belief(pit_detected)) {
                write "Breeze detected! Retreating...";
            }
            if (has_belief(wumpus_detected)) {
                write "Odor detected! Retreating...";
            }
        }
        
        do remove_belief(danger_detected);
        do remove_belief(pit_detected);
        do remove_belief(wumpus_detected);
        do remove_intention(escape_danger_desire, true);
    }
    
    // PLAN 2: GO TO GOLD - High priority
    plan go_to_gold intention: collect_gold_desire priority: 8 {
        // Find gold if no target
        if (gold_target = nil) {
            if (!empty(goldArea)) {
                goldArea nearest <- goldArea closest_to self;
                gold_target <- nearest.location;
                write "New gold target: " + gold_target;
            } else if (!empty(known_gold_locations)) {
                gold_target <- known_gold_locations[length(known_gold_locations) - 1];
            } else {
                do remove_intention(collect_gold_desire, true);
                do add_desire(explore_desire);
                return;
            }
        }
        
        // Check if reached gold
        if (location distance_to gold_target < 3.0) {
            list<goldArea> nearby_gold <- goldArea at_distance 3.0;
            if (!empty(nearby_gold)) {
                write "Gold collected at step " + steps_taken + "!";
                gold_collected <- gold_collected + 1;
                
                ask nearby_gold {
                    do die;
                }
                ask glitterArea {
                    do die;
                }
                
                gold_target <- nil;
                do remove_belief(gold_detected);
                do remove_intention(collect_gold_desire, true);
                do add_desire(explore_desire);
                return;
            }
        }
        
        // Move toward gold using simple movement (not goto)
        previous_cell <- my_cell;
        gworld next_cell <- get_next_cell_toward(gold_target);
        
        if (next_cell != nil) {
            my_cell <- next_cell;
            location <- my_cell.location;
            add location to: visited_locations;
            do check_hazards;
        } else {
            write "Cannot reach gold, exploring instead";
            gold_target <- nil;
            do remove_intention(collect_gold_desire, true);
            do add_desire(explore_desire);
        }
    }
    
    // PLAN 3: EXPLORE - Medium priority
    plan explore_unvisited intention: explore_desire priority: 5 {
        // Find distant unvisited cell
        if (exploration_target = nil or location distance_to exploration_target < 3.0) {
            list<gworld> candidates <- [];
            
            // Look for unvisited cells far from current location
            loop cell over: gworld {
                if (location distance_to cell.location > 10 and location distance_to cell.location < 30) {
                    bool already_visited <- false;
                    loop visited_loc over: visited_locations {
                        if (cell.location distance_to visited_loc < 3.0) {
                            already_visited <- true;
                            break;
                        }
                    }
                    
                    if (!already_visited) {
                        bool is_safe <- true;
                        
                        // Check safety
                        loop pit_loc over: known_pit_locations {
                            if (cell.location distance_to pit_loc < 4.0) {
                                is_safe <- false;
                                break;
                            }
                        }
                        
                        loop wumpus_loc over: known_wumpus_locations {
                            if (cell.location distance_to wumpus_loc < 4.0) {
                                is_safe <- false;
                                break;
                            }
                        }
                        
                        if (is_safe) {
                            add cell to: candidates;
                        }
                    }
                }
            }
            
            if (!empty(candidates)) {
                exploration_target <- (one_of(candidates)).location;
                write "New exploration target: " + exploration_target;
            }
        }
        
        if (exploration_target != nil) {
            // Move toward exploration target
            previous_cell <- my_cell;
            gworld next_cell <- get_next_cell_toward(exploration_target);
            
            if (next_cell != nil) {
                my_cell <- next_cell;
                location <- my_cell.location;
                
                // Track visit
                if (length(visited_locations) >= max_memory_visits) {
                    remove index: 0 from: visited_locations;
                }
                add location to: visited_locations;
                
                do check_hazards;
            }
        } else {
            // Fallback to patrol
            do remove_intention(explore_desire, true);
            do add_desire(patrol_desire);
        }
    }
    
    // PLAN 4: PATROL - Lowest priority
    plan patrol_plan intention: patrol_desire priority: 1 {
        previous_cell <- my_cell;
        gworld next_cell <- get_safe_unvisited_neighbor();
        
        if (next_cell != nil) {
            my_cell <- next_cell;
            location <- my_cell.location;
            
            if (length(visited_locations) >= max_memory_visits) {
                remove index: 0 from: visited_locations;
            }
            add location to: visited_locations;
            
            do check_hazards;
        } else {
            // Force exploration if no unvisited neighbors
            do remove_intention(patrol_desire, true);
            do add_desire(explore_desire);
        }
    }
    
    // Helper: Get next cell toward target
    gworld get_next_cell_toward(point target) {
        list<gworld> valid_neighbors <- [];
        
        loop neighbor over: my_cell.neighbors {
            bool is_safe <- is_cell_safe(neighbor);
            
            if (is_safe) {
                add neighbor to: valid_neighbors;
            }
        }
        
        if (empty(valid_neighbors)) {
            return nil;
        }
        
        // Choose neighbor closest to target
        gworld best_neighbor <- valid_neighbors closest_to target;
        return best_neighbor;
    }
    
    // Helper: Get unvisited safe neighbor
    gworld get_safe_unvisited_neighbor {
        list<gworld> unvisited_neighbors <- [];
        
        loop neighbor over: my_cell.neighbors {
            bool is_safe <- is_cell_safe(neighbor);
            bool is_unvisited <- true;
            
            loop visited_loc over: visited_locations {
                if (neighbor.location distance_to visited_loc < 2.0) {
                    is_unvisited <- false;
                    break;
                }
            }
            
            if (is_safe and is_unvisited) {
                add neighbor to: unvisited_neighbors;
            }
        }
        
        if (!empty(unvisited_neighbors)) {
            return one_of(unvisited_neighbors);
        }
        
        // If all visited, choose any safe neighbor
        list<gworld> safe_neighbors <- [];
        loop neighbor over: my_cell.neighbors {
            if (is_cell_safe(neighbor)) {
                add neighbor to: safe_neighbors;
            }
        }
        
        if (!empty(safe_neighbors)) {
            return one_of(safe_neighbors);
        }
        
        return nil;
    }
    
    // Helper: Check if cell is safe
    bool is_cell_safe(gworld cell) {
        // Check known hazards
        loop pit_loc over: known_pit_locations {
            if (cell.location distance_to pit_loc < 3.0) {
                return false;
            }
        }
        
        loop wumpus_loc over: known_wumpus_locations {
            if (cell.location distance_to wumpus_loc < 3.0) {
                return false;
            }
        }
        
        // Check direct collision
        bool has_pit <- false;
        bool has_wumpus <- false;
        
        ask pitArea {
            if (self.location distance_to cell.location < 1.0) {
                has_pit <- true;
            }
        }
        
        ask wumpusArea {
            if (self.location distance_to cell.location < 1.0) {
                has_wumpus <- true;
            }
        }
        
        return !has_pit and !has_wumpus;
    }
    
    // Hazard checking
    action check_hazards {
        if (!empty(pitArea at_distance 2.0)) {
            write "Player fell into a pit!";
            deaths_by_pit <- deaths_by_pit + 1;
            game_over <- true;
            is_alive <- false;
            do die;
        }
        
        if (!empty(wumpusArea at_distance 2.0)) {
            write "Player eaten by Wumpus!";
            deaths_by_wumpus <- deaths_by_wumpus + 1;
            game_over <- true;
            is_alive <- false;
            do die;
        }
    }
    
    // COLLISION DETECTION
    reflex check_pit_collision when: is_alive {
        if (!empty(pitArea at_distance 2.0)) {
            write "Player fell into a pit at step " + steps_taken;
            deaths_by_pit <- deaths_by_pit + 1;
            game_over <- true;
            is_alive <- false;
            do die;
        }
    }
    
    reflex check_wumpus_collision when: is_alive {
        if (!empty(wumpusArea at_distance 2.0)) {
            write "Player eaten by Wumpus at step " + steps_taken;
            deaths_by_wumpus <- deaths_by_wumpus + 1;
            game_over <- true;
            is_alive <- false;
            do die;
        }
    }
    
    reflex check_gold_collection when: is_alive {
        list<goldArea> nearby_gold <- goldArea at_distance 3.0;
        if (!empty(nearby_gold)) {
            gold_collected <- gold_collected + 1;
            total_gold_collected <- total_gold_collected + 1;
            
            ask nearby_gold {
                do die;
            }
            ask glitterArea {
                do die;
            }
            
            if (total_gold_collected >= gold_to_win) {
                write "VICTORY at step " + steps_taken + "!";
                player_won <- true;
                game_over <- true;
                is_alive <- false;
                do die;
            } else {
                create goldArea number: 1;
            }
            
            gold_target <- nil;
        }
    }
    
    aspect base {
        draw circle(2) color: #blue border: #darkblue;
    }
}

experiment GUI_Experiment type: gui {
	parameter "Difficulty" var: difficulty <- "GUI";
    output {
        display view1 { 
            grid gworld border: #darkgreen;
            species goldArea aspect: base;
            species glitterArea aspect: base;
            species wumpusArea aspect: base;
            species odorArea aspect: base;
            species pitArea aspect: base;
            species breezeArea aspect: base;
            species player aspect: base;
        }
        
        monitor "Steps" value: steps_taken;
        monitor "Gold Progress" value: string(total_gold_collected) + " / " + string(gold_to_win);
        monitor "Game Status" value: player_won ? "🏆 VICTORY!" : (game_over ? "💀 GAME OVER" : "▶ Playing");
    }
}


experiment Full_Exploration type: batch repeat: 5 keep_seed: false until: (cycle >= 5000) {
    parameter "Batch Mode" var: is_batch <- true;
    
    // These parameters with "among" automatically trigger exhaustive exploration
    parameter "Number of Pits" var: num_pits among: [1, 2, 3];
    parameter "Number of Wumpus" var: num_wumpus among: [1, 2];
    parameter "Gold to Win" var: gold_to_win among: [2, 3, 4];
    parameter "Grid Size" var: grid_size among: [15, 25];
    
    
    reflex save_all_results {
        ask simulations {
        	
            save [
                self.player_won ? "WIN" : "LOSS",
                self.total_gold_collected,
                self.steps_taken,
                self.deaths_by_pit,
                self.deaths_by_wumpus,
                self.num_pits,
                self.num_wumpus,
                self.gold_to_win,
                self.initial_player_position != nil ? int(self.initial_player_position.x) : 0,
                self.initial_player_position != nil ? int(self.initial_player_position.y) : 0,
                self.grid_size
            ] to: "full_exploration_results_goto.csv" 
            rewrite: false
            format: "csv";
        }
        
    }
}
