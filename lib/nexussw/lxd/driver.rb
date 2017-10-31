require 'nexussw/lxd'

module NexusSW
  module LXD
    module Driver
      STATUS_CODES = {
        100	=> 'created',
        101	=> 'started',
        102	=> 'stopped',
        103	=> 'running',
        104	=> 'cancelling',
        105	=> 'pending',
        106	=> 'starting',
        107	=> 'stopping',
        108	=> 'aborting',
        109	=> 'freezing',
        110	=> 'frozen',
        111	=> 'thawed',
        200	=> 'success',
        400	=> 'failure',
        401	=> 'cancelled',
      }.freeze

      # def create_container(_container_name, _container_options)
      # def start_container(_container_id)
      # def stop_container(_container_id, _options = {})
      # def delete_container(_container_id)
      # def container_status(_container_id)
      # def container(_container_id)
    end
  end
end
