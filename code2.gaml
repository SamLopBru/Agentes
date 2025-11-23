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
        
        create goldArea number: 1;
        create wumpusArea number: num_wumpus;
        create pitArea number: num_pits;
        create player number: 1;
    }
    
    reflex count_steps {
        steps_taken <- steps_taken + 1;
        
        // Individual simulation timeout
        if (steps_taken >= 5000 and !game_over) {
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
        gworld place <- one_of(gworld);
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
    
    // Predicates for desires
    predicate patrol_desire <- new_predicate("patrol");
    predicate collect_gold_desire <- new_predicate("collect_gold");
    predicate avoid_wumpus_desire <- new_predicate("avoid_wumpus");
    predicate avoid_pit_desire <- new_predicate("avoid_pit");
    predicate escape_danger_desire <- new_predicate("escape_danger");
    
    // Memory
    list<point> known_pit_locations <- [];
    int max_memory_pits <- 5;
    list<point> known_gold_locations <- [];
    int max_memory_gold <- 3;
    
    bool is_alive <- true;
    int gold_collected <- 0;
    
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
    
    // Store initial position
    initial_player_position <- location;
    
    write "Player starting at: " + location;
    
    do add_desire(patrol_desire);
    do add_desire(avoid_pit_desire);
    do add_desire(avoid_wumpus_desire);
}

    
    // PERCEPTIONS
    perceive target: breezeArea in: 1 {
        focus id: "breeze_detected" var: location strength: 8.0;
        ask myself {
            do add_belief(pit_detected);
            do add_belief(danger_detected);
            do add_desire(escape_danger_desire);
            
            if (length(known_pit_locations) >= max_memory_pits) {
                remove index: 0 from: known_pit_locations;
            }
            add myself.location to: known_pit_locations;
        }
    }

    perceive target: odorArea in: 1 {
        focus id: "odor_detected" var: location strength: 9.0;
        ask myself {
            do add_belief(wumpus_detected);
            do add_belief(danger_detected);
            do add_desire(escape_danger_desire);
        }
    }

    perceive target: glitterArea in: 1 {
        focus id: "glitter_detected" var: location strength: 10.0;
        ask myself {
            do add_belief(gold_detected);
            do add_desire(collect_gold_desire);
            
            if (length(known_gold_locations) >= max_memory_gold) {
                remove index: 0 from: known_gold_locations;
            }
            add myself.location to: known_gold_locations;
        }
    }
    
    // RULES - Can add specific rules for each danger
    rule belief: pit_detected new_desire: escape_danger_desire strength: 9.0;
    rule belief: wumpus_detected new_desire: escape_danger_desire strength: 9.0;
    rule belief: danger_detected new_desire: escape_danger_desire strength: 9.0;
    
    // SINGLE REUSABLE PLAN - handles both pit and wumpus
    plan escape_plan intention: escape_danger_desire priority: 10 {
        if (previous_cell != nil and previous_cell != my_cell) {
            my_cell <- previous_cell;
            location <- my_cell.location;
            
            // More informative message
            if (has_belief(pit_detected)) {
                write "Detected breeze! Moving away from pit.";
            }
            if (has_belief(wumpus_detected)) {
                write "Detected odor! Moving away from Wumpus.";
            }
        }
        
        // Clear all danger beliefs
        do remove_belief(danger_detected);
        do remove_belief(pit_detected);
        do remove_belief(wumpus_detected);
        do remove_intention(escape_danger_desire, true);
    }
    
    // Plan 2: Move randomly near glitter to find gold
    plan search_gold_plan intention: collect_gold_desire priority: 5 {
        if (!empty(goldArea at_distance 1)) {
            write "Gold collected!";
            gold_collected <- gold_collected + 1;
            
            ask goldArea at_distance 1 {
                do die;
            }
            ask glitterArea {
                do die;
            }
            do remove_intention(collect_gold_desire, true);
            do remove_belief(gold_detected);
        } else {
            // Move toward glitter but check safety
            list<gworld> safe_neighbors <- [];
            
            loop neighbor over: my_cell.neighbors {
                bool is_dangerous <- false;
                
                // Check if this neighbor is a pit or wumpus
                ask pitArea {
                    if (self.location = neighbor.location) {
                        is_dangerous <- true;
                    }
                }
                
                ask wumpusArea {
                    if (self.location = neighbor.location) {
                        is_dangerous <- true;
                    }
                }
                
                if (!is_dangerous) {
                    add neighbor to: safe_neighbors;
                }
            }
            
            if (!empty(safe_neighbors)) {
                previous_cell <- my_cell;
                my_cell <- one_of(safe_neighbors);
                location <- my_cell.location;
            }
        }
    }

    // Plan 3: Patrol when no specific goals
    plan patrol_plan intention: patrol_desire priority: 1 {
        list<gworld> safe_neighbors <- [];
        
        loop neighbor over: my_cell.neighbors {
            bool is_dangerous <- false;
            
            // Check if this neighbor is a pit or wumpus
            ask pitArea {
                if (self.location = neighbor.location) {
                    is_dangerous <- true;
                }
            }
            
            ask wumpusArea {
                if (self.location = neighbor.location) {
                    is_dangerous <- true;
                }
            }
            
            if (!is_dangerous) {
                add neighbor to: safe_neighbors;
            }
        }
        
        if (!empty(safe_neighbors)) {
            previous_cell <- my_cell;
            my_cell <- one_of(safe_neighbors);
            location <- my_cell.location;
        }
        // Stay put if no safe neighbors
    }
    
    // COLLISION DETECTION
    reflex check_pit_collision when: is_alive {
        if (!empty(pitArea at_distance 0.5)) {
            write "Player fell into a pit at step " + steps_taken;
            deaths_by_pit <- deaths_by_pit + 1;
            game_over <- true;
            is_alive <- false;
            do die;
        }
    }
    
    reflex check_wumpus_collision when: is_alive {
        if (!empty(wumpusArea at_distance 0.5)) {
            write "Player eaten by Wumpus at step " + steps_taken;
            deaths_by_wumpus <- deaths_by_wumpus + 1;
            game_over <- true;
            is_alive <- false;
            do die;
        }
    }
    
    reflex check_gold_collection when: is_alive {
        list<goldArea> nearby_gold <- goldArea at_distance 0.5;
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


experiment Full_Exploration type: batch repeat: 10 keep_seed: false until: (cycle >= 5000) {
    parameter "Batch Mode" var: is_batch <- true;
    
    // These parameters with "among" automatically trigger exhaustive exploration
    parameter "Number of Pits" var: num_pits among: [1, 2, 3];
    parameter "Number of Wumpus" var: num_wumpus among: [1, 2];
    parameter "Gold to Win" var: gold_to_win among: [2, 3, 4];
    
    
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
            ] to: "full_exploration_results_conservative.csv" 
            rewrite: false
            format: "csv";
        }
        
    }
}


