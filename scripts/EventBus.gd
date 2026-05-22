# scripts/EventBus.gd
extends Node
# 全システムのシグナルを中央集権でルーティングするバス

# --- Game Flow ---
@warning_ignore("unused_signal")
signal phase_changed(new_phase: int)
@warning_ignore("unused_signal")
signal num_error_triggered()
@warning_ignore("unused_signal")
signal prestige_done(layer: int)

# --- Cells ---
@warning_ignore("unused_signal")
signal cells_updated()
@warning_ignore("unused_signal")
signal cell_clicked(cell_id: String)

# --- Upgrades ---
@warning_ignore("unused_signal")
signal upgrade_applied(upg_id: String)

# --- Progression ---
@warning_ignore("unused_signal")
signal layer_unlocked(layer: int)
