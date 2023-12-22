local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Packages = script.Parent
local Promise = require(Packages.Promise)
local Signal = require(Packages.Signal)
local Janitor = require(Packages.Janitor)
local TaskUtil = require(script.TaskUtil)

type Cleanup = () -> ()
type Callback = (...any) -> Cleanup

local DEFAULT_TIMEOUT = 60
local DEFAULT_ANCESTORS = { workspace }

local function add(self, instance)
	assert(typeof(instance) == "Instance", "Argument 'instance' is not an Instance")

	if self._instToClass[instance] then
		-- https://devforum.roblox.com/t/double-firing-of-collectionservice-getinstanceaddedsignal-when-applying-tag/244235

		return
	end

	if self._pendingInstSet[instance] == true then
		warn("[Binder._add] - Reentered add. Still loading, probably caused by error in constructor.")

		return
	end

	self._pendingInstSet[instance] = true

	local class

	if type(self._constructor) == "function" then
		class = self._constructor(instance, table.unpack(self._args))
	end

	if type(self._constructor) == "table" then
		if self._constructor.Create then
			class = self._constructor:Create(instance, table.unpack(self._args))
		else
			class = self._constructor.new(instance, table.unpack(self._args))
		end
	end

	if self._pendingInstSet[instance] ~= true then
		-- Got GCed in the process of loading?!
		-- Constructor probably yields. Yikes.
		warn(
			("[Binder._add] - Failed to load instance %q of %q, removed while loading!"):format(
				instance:GetFullName(),
				tostring(type(self._constructor) == "table" and self._constructor.ClassName or self._constructor)
			)
		)
		return
	end

	self._pendingInstSet[instance] = nil
	assert(self._instToClass[instance] == nil, "Overwrote")

	class = if class then class else {}

	-- Add to state
	self._allClassSet[class] = true
	self._instToClass[instance] = class

	-- Fire events
	local listeners = self._listeners[instance]

	if listeners then
		for callback in listeners do
			task.spawn(callback, class)
		end
	end

	if self._classAddedSignal then
		self._classAddedSignal:Fire(class, instance)
	end
end

local function remove(self, instance)
	assert(typeof(instance) == "Instance", "Argument 'instance' is not an Instance")

	self._pendingInstSet[instance] = nil

	local class = self._instToClass[instance]

	if not class then
		return
	end

	-- Fire off events
	if self._classRemovingSignal then
		self._classRemovingSignal:Fire(class, instance)
	end

	-- Fire listeners here
	local listeners = self._listeners[instance]

	if listeners then
		for callback in listeners do
			task.spawn(callback, nil)
		end
	end

	-- Clean up state
	self._instToClass[instance] = nil
	self._allClassSet[class] = nil

	if TaskUtil.isValidTask(class) then
		TaskUtil.doTask(class)
	end

	-- Fire off events
	if self._classRemovedSignal then
		self._classRemovedSignal:Fire(class, instance)
	end
end

--[=[
	@class Binder

	Bind class to Roblox Instance

	```lua
	-- Setup a class!
	local MyClass = {}
	MyClass.__index = MyClass

	function MyClass.new(robloxInstance)
		print("New tagged instance of ", robloxInstance)
		return setmetatable({}, MyClass)
	end

	function MyClass:Destroy()
		print("Cleaning up")
		setmetatable(self, nil)
	end

	-- bind to every instance with tag of "TagName"!
	local config = {
		TagName = "TagName",
		Ancestors = {workspace}
	}
	local binder = Binder.new(config, MyClass)
	binder:Start() -- listens for new instances and connects events
	```
]=]
local Binder = {}
Binder.__index = Binder
Binder.ClassName = "Binder"

--[=[
	@within Binder
	@interface BinderConfig
	@field TagName string  -- Name of the tag to bind to. This uses CollectionService's tag system
	@field Ancestors {Instance}? 
]=]

--[=[
	@within Binder
	@type BinderContructor (Instance, ...: any) -> T | { new: (Instance, ...: any) } | { Create(self, Instance, ...: any) }

	Constructor for a binder
]=]

--[=[
	@within Binder
	@param config BinderConfig
	@param constructor BinderConstructor
	@param ... any -- Variable arguments that will be passed into the constructor
	@return Binder<T>

	Constructs a new binder object.

	```lua
	local config = {
		TagName = "Bird",
		Ancestors = {workspace}
	}
	local binder = Binder.new(config, function(inst)
		print("Wow, a new bird!", inst)

		return {
			Destroy = function()
				print("Uh oh, the bird is gone!")
			end;
		}
	end)

	binder:Start()
	```
]=]
function Binder.new(config, constructor, ...)
	local self = setmetatable({}, Binder)

	self._maid = Janitor.new()
	self._tagName = config.TagName or error("Bad argument in 'config.TagName', expected string")
	self._ancestors = config.Ancestors or DEFAULT_ANCESTORS
	self._constructor = constructor or error("Bad argument 'constructor', expected table or function")

	self._instToClass = {} -- [inst] = class
	self._allClassSet = {} -- [class] = true
	self._pendingInstSet = {} -- [inst] = true
	self._listeners = {} -- [inst] = callback
	self._ancestryConnectionIds = {} -- [inst] = string

	self._args = table.pack(...)

	self._classAddedSignal = self._maid:Add(Signal.new(), "Destroy")
	self._classRemovingSignal = self._maid:Add(Signal.new(), "Destroy")
	self._classRemovedSignal = self._maid:Add(Signal.new(), "Destroy")

	return self
end

--[=[
	@within Binder
	@param value Binder<T>?
	@return boolean

	Retrieves whether or not the given value is a binder.
]=]
function Binder.isBinder(value)
	return type(value) == "table"
		and type(value.Start) == "function"
		and type(value.Get) == "function"
		and type(value.GetTag) == "function"
		and type(value.GetConstructor) == "function"
		and type(value.GetClassAddedSignal) == "function"
		and type(value.GetClassRemovingSignal) == "function"
		and type(value.GetClassRemovedSignal) == "function"
		and type(value.GetAll) == "function"
		and type(value.GetAllSet) == "function"
		and type(value.Bind) == "function"
		and type(value.Unbind) == "function"
		and type(value.BindClient) == "function"
		and type(value.UnbindClient) == "function"
		and type(value.ObserveInstance) == "function"
		and type(value.Promise) == "function"
		and type(value.Destroy) == "function"
end

--[=[
	@within Binder
	@return nil

	Starts the binder and listens for new instances
	and connects to the `:GetInstanceAddedSignal()` and `:GetInstanceRemovedSignal()` signals.
]=]
function Binder:Start()
	if self._loaded then
		return
	end

	self._loaded = true

	local function isGoodAncestor(instance)
		for _, ancestor in self._ancestors do
			if instance:IsDescendantOf(ancestor) then
				return true
			end
		end

		return false
	end

	local function onAncestryChanged(instance)
		if not isGoodAncestor(instance) then
			remove(self, instance)
		end

		if not self._instToClass[instance] then
			add(self, instance)
		end
	end

	local function onInstanceAdded(instance)
		self._ancestryConnectionIds[instance] = HttpService:GenerateGUID(false)

		onAncestryChanged(instance)
		self._maid:Add(
			instance.AncestryChanged:Connect(onAncestryChanged),
			"Disconnect",
			self._ancestryConnectionIds[instance]
		)
	end

	local function onInstanceRemoved(instance: Instance)
		local ancestryConnectionId = self._ancestryConnectionIds[instance]
		self._ancestryConnectionIds[instance] = nil

		remove(self, instance)
		self._maid:Remove(ancestryConnectionId)
	end

	self._maid:Add(CollectionService:GetInstanceAddedSignal(self._tagName):Connect(onInstanceAdded), "Disconnect")
	self._maid:Add(CollectionService:GetInstanceRemovedSignal(self._tagName):Connect(onInstanceRemoved), "Disconnect")

	for _, instance in CollectionService:GetTagged(self._tagName) do
		task.defer(onInstanceAdded, instance)
	end
end

--[=[
	@within Binder
	@return string

	Returns the tag name that the binder has.
]=]
function Binder:GetTag()
	return self._tagName
end

--[=[
	@within Binder
	@return BinderContructor

	Returns whatever was set for the construtor. Used for meta-analysis of
	the binder, such as extracting if parameters are allowed.
]=]
function Binder:GetConstructor()
	return self._constructor
end

--[=[
	@within Binder
	@param instance Instance
	@param callback function 
	@return function -- Cleanup function
	
	Fired when added, and then after removal, but before destroy!
]=]
function Binder:ObserveInstance(instance: Instance, callback: Callback)
	self._listeners[instance] = if self._listeners[instance] then self._listeners[instance] else {}
	self._listeners[instance][callback] = true

	return function()
		if not self._listeners[instance] then
			return
		end

		self._listeners[instance][callback] = nil

		if not next(self._listeners[instance]) then
			self._listeners[instance] = nil
		end
	end
end

--[=[
	@within Binder
	@return Signal<T>

	Returns a new signal that will fire whenever a class is bound to the binder

	```lua
	local config = {
		TagName = "Bird",
		Ancestors = {workspace}
	}
	local birdBinder = Binder.new(config, require("Bird")) -- Load bird into binder

	birdBinder:GetClassAddedSignal():Connect(function(bird)
		bird:Squack() -- Make the bird squack when it's first spawned
	end)

	-- Load all birds
	birdBinder:Start()
	```
]=]
function Binder:GetClassAddedSignal()
	return self._classAddedSignal
end

--[=[
	@within Binder
	@return Signal<T>

	Returns a new signal that will fire whenever a class is removing from the binder.
]=]
function Binder:GetClassRemovingSignal()
	return self._classRemovingSignal
end

--[=[
	@within Binder
	@return Signal<T>

	Returns a new signal that will fire whenever a class is removed from the binder.
]=]
function Binder:GetClassRemovedSignal()
	return self._classRemovedSignal
end

--[=[
	@within Binder
	@return {T}

	Returns all of the classes in a new table.

	```lua
	local config = {
		TagName = "Bird",
		Ancestors = {workspace}
	}
	local birdBinder = Binder.new(config, require("Bird")) -- Load bird into binder

	-- Update every bird every frame
	RunService.Stepped:Connect(function()
		for _, bird in pairs(birdBinder:GetAll()) do
			bird:Update()
		end
	end)

	birdBinder:Start()
	```
]=]
function Binder:GetAll()
	local all = {}

	for class in self._allClassSet do
		table.insert(all, class)
	end

	return all
end

--[=[
	@within Binder
	@return { [T]: boolean }

	Faster method to get all items in a binder

	```lua
	local config = {
		TagName = "Bird",
		Ancestors = {workspace}
	}
	local birdBinder = Binder.new(config, require("Bird")) -- Load bird into binder

	-- Update every bird every frame
	RunService.Stepped:Connect(function()
		for bird, _ in pairs(birdBinder:GetAllSet()) do
			bird:Update()
		end
	end)

	birdBinder:Start()
	```

	:::warning
	Do not mutate this set directly
	:::
]=]
function Binder:GetAllSet()
	return self._allClassSet
end

--[=[
	@within @server Binder
	@param instance Instance -- Instance to bind
	@return nil

	Binds an instance to this binder using collection service and attempts
	to return it if it's bound properly. See `:Promise()` for a safe
	way to retrieve it.

	:::warning
	Do not assume that a bound object will be retrieved
	:::
]=]
function Binder:Bind(instance)
	if RunService:IsClient() then
		warn(
			("[Binder.Bind] - Bindings '%s' done on the client! Will be disrupted upon server replication! %s"):format(
				self._tagName,
				debug.traceback()
			)
		)
	end

	CollectionService:AddTag(instance, self._tagName)
end

--[=[
	@within @server Binder
	@param instance Instance -- Instance to unbind
	@return nil

	Unbinds the instance by removing the tag.
]=]
function Binder:Unbind(instance)
	assert(typeof(instance) == "Instance", "Bad inst'")

	if RunService:IsClient() then
		warn(
			("[Binder.Bind] - Unbinding '%s' done on the client! Might be disrupted upon server replication! %s"):format(
				self._tagName,
				debug.traceback()
			)
		)
	end

	CollectionService:RemoveTag(instance, self._tagName)
end

--[=[
	@within @client Binder
	@param instance Instance -- Instance to bind
	@return nil

	See `:Bind()`. Acknowledges the risk of doing this on the client. Using this method
	acknowledges that we're intentionally binding on a safe client object (one without
	replication). If another tag is changed on this instance, this tag will be lost/changed.
]=]
function Binder:BindClient(instance)
	if not RunService:IsClient() then
		warn(("[Binder.BindClient] - Bindings '%s' done on the server! Will be replicated!"):format(self._tagName))
	end

	CollectionService:AddTag(instance, self._tagName)
end

--[=[
	@within @client Binder
	@param instance Instance -- Instance to unbind
	@return nil

	See `:Unbind()`, acknowledges risk of doing this on the client. 
]=]
function Binder:UnbindClient(instance)
	assert(typeof(instance) == "Instance", "Bad inst")
	CollectionService:RemoveTag(instance, self._tagName)
end

--[=[
	@within Binder
	@param instance Instance -- Instance to check
	@return T?
	
	Returns a instance of the class that is bound to the instance given.
]=]
function Binder:Get(instance)
	assert(typeof(instance) == "Instance", "Argument 'inst' is not an Instance")

	return self._instToClass[instance]
end

--[=[
	@within Binder
	@param instance Instance -- Instance to check
	@param timeout number?
	@return Promise<T>

	Returns a promise which will resolve when the instance is bound.
]=]
function Binder:Promise(instance, timeout)
	if typeof(instance) ~= "Instance" then
		error("[Binder.Promise] - Argument 'instance' is not an Instance")

		return
	end

	if timeout and type(timeout) ~= "number" then
		error("[Binder.Promise] - Argument 'timeout' is not an number")

		return
	end

	local binderInstance = self:Get(instance)

	if binderInstance then
		return Promise.resolve(binderInstance)
	end

	return Promise.fromEvent(self._classAddedSignal, function(binderInst, inst: Instance)
		local doesMatch = inst == instance

		if doesMatch then
			binderInstance = binderInst
		end

		return doesMatch
	end)
		:andThen(function()
			return binderInstance
		end)
		:timeout(if timeout then timeout else DEFAULT_TIMEOUT)
end

--[=[
	@within Binder
	@return nil

	Cleans up all bound classes, disconnects all events and destroys the binder itself.
]=]
function Binder:Destroy()
	for instance: Instance in self._instToClass do
		remove(self, instance)
		assert(self._instToClass[instance] == nil, "Failed to remove")
	end

	self._maid:Destroy()

	table.clear(self)
	setmetatable(self, nil)
end

return Binder
