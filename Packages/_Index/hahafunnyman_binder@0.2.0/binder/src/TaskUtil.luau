--[=[
	@class TaskUtil

	Utility methods involving maids and tasks.
]=]
local TaskUtil = {}

type callback = () -> ()

--[=[
	@within TaskUtil
	@type MaidTask function | thread | Destructable | RBXScriptConnection
	
	An object that can be cleaned up
]=]
type MaidTask = (thread | RBXScriptConnection | callback | Destructable)

--[=[
	@within TaskUtil
	@type Destructable Instance | { Destroy: function }

	An object that can have the method :Destroy() called on it
]=]
type Destructable = Instance | { Destroy: (self: any) -> () }

--[=[
	@within TaskUtil
	@param job MaidTask
	@return boolean

	Returns whether a task is a valid job.
]=]
function TaskUtil.isValidTask(job: MaidTask): boolean
	return type(job) == "function"
		or type(job) == "thread"
		or typeof(job) == "RBXScriptConnection"
		or type(job) == "table" and type(job.Destroy) == "function"
		or typeof(job) == "Instance"
end

--[=[
	@within TaskUtil
	@param job MaidTask -- Task to execute
	@return nil

	Executes the task as requested.
]=]
function TaskUtil.doTask(job: MaidTask)
	if type(job) == "function" then
		job()
	elseif type(job) == "thread" then
		local cancelled
		if coroutine.running() ~= job then
			cancelled = pcall(function()
				task.cancel(job)
			end)
		end

		if not cancelled then
			task.defer(function()
				task.cancel(job)
			end)
		end
	elseif typeof(job) == "RBXScriptConnection" then
		job:Disconnect()
	elseif type(job) == "table" and type(job.Destroy) == "function" then
		job:Destroy()
	elseif typeof(job) == "Instance" then
		(job :: Instance):Destroy()
	else
		error("Bad job")
	end
end

--[=[
	@within TaskUtil
	@param time number -- Time in seconds
	@param job MaidTask -- Job to delay execution
	@return function -- function that will execute the job delayed
	
	Executes the task delayed after some time.

	```lua
	-- delays cleanup by 5 seconds
	maid:GiveTask(TaskUtil.delayed(5, gui))
	```
]=]
function TaskUtil.delayed(time, job)
	assert(type(time) == "number", "Bad time")
	assert(TaskUtil.isValidTask(job), "Bad job")

	return function()
		task.delay(time, function()
			TaskUtil.doTask(job)
		end)
	end
end

return TaskUtil
