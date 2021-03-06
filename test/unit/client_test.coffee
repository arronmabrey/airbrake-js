chai = require("chai")
sinon = require("sinon")
sinon_chai = require("sinon-chai")
expect = chai.expect
chai.use(sinon_chai)

Client = require("../../src/client")


testWrap = (client) ->
  describe "wrap", ->
    it "does not invoke function immediately", ->
      fn = sinon.spy()
      client.wrap(fn)
      expect(fn).not.to.have.been.called

    it "creates wrapper that invokes function with passed args", ->
      fn = sinon.spy()
      wrapper = client.wrap(fn)
      wrapper("hello", "world")
      expect(fn).to.have.been.called
      expect(fn.lastCall.args).to.deep.equal(["hello", "world"])

    it "sets __airbrake__ and __inner__ properties", ->
      fn = sinon.spy()
      wrapper = client.wrap(fn)
      expect(wrapper.__airbrake__).to.equal(true)
      expect(wrapper.__inner__).to.equal(fn)

    it "copies function properties", ->
      fn = sinon.spy()
      fn.prop = "hello"
      wrapper = client.wrap(fn)
      expect(wrapper.prop).to.equal("hello")

    it "reports throwed exception", ->
      client.notify = sinon.spy()
      exc = new Error("test")
      fn = ->
        throw exc
      wrapper = client.wrap(fn)
      wrapper("hello", "world")
      expect(client.notify).to.have.been.called
      expect(client.notify.lastCall.args).to.deep.equal([{error: exc, params: {arguments: ["hello", "world"]}}])

    it "wraps arguments", ->
      fn = sinon.spy()
      wrapper = client.wrap(fn)
      arg1 = ->
      wrapper(arg1)
      expect(fn).to.have.been.called
      arg1Wrapper = fn.lastCall.args[0]
      expect(arg1Wrapper.__airbrake__).to.equal(true)
      expect(arg1Wrapper.__inner__).to.equal(arg1)


describe "Client", ->
  clock = undefined

  beforeEach ->
    clock = sinon.useFakeTimers()

  afterEach ->
    clock.restore()

  processor = null
  reporter = null
  client = null

  beforeEach ->
    processor = sinon.spy (data, cb) ->
      cb(data)
    reporter = sinon.spy (_, __, promise) ->
      promise.resolve({id: 1})
    client = new Client(processor: processor, reporter: reporter)

  describe 'filter', ->
    it 'returns false to ignore notice', ->
      filter = sinon.spy (notice) -> false
      client.addFilter(filter)

      client.notify({})

      expect(filter).to.have.been.called
      expect(reporter).not.to.have.been.called

    it 'returns true to pass notice', ->
      filter = sinon.spy (notice) -> true
      client.addFilter(filter)

      client.notify(error: {})

      expect(filter).to.have.been.called
      expect(reporter).to.have.been.called

    it 'returns notice to change payload', ->
      filter = sinon.spy (notice) ->
        notice.context.environment = 'production'
      client.addFilter(filter)

      client.notify(error: {})

      expect(filter).to.have.been.called
      notice = reporter.lastCall.args[0]
      expect(notice.context.environment).to.equal('production')

  describe "notify", ->
    exception = do ->
      error = undefined
      try
        (0)()
      catch _err
        error = _err
      return error

    it "returns promise and resolves it", ->
      promise = client.notify(exception)
      onResolved = sinon.spy()
      promise.then(onResolved)
      expect(onResolved).to.have.been.called

    describe "with error", ->
      it "processor is called", ->
        client.notify(exception)

        expect(processor).to.have.been.called

      it "reporter is called with valid options", ->
        client.setProject(999, "custom_project_key")
        client.notify(exception)

        expect(reporter).to.have.been.called
        opts = reporter.lastCall.args[1]
        expect(opts).to.deep.equal({
          projectId: 999
          projectKey: "custom_project_key",
          host: "https://api.airbrake.io"
        })

      it "reporter is called with custom host", ->
        client.setHost("https://custom.domain.com")
        client.notify(exception)

        reported = reporter.lastCall.args[1]
        expect(reported.host).to.equal("https://custom.domain.com")

    describe "custom data sent to reporter", ->
      it "reports context", ->
        client.addContext(context_key: "[custom_context]")
        client.notify(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.context.context_key).to.equal("[custom_context]")

      it "reports environment name", ->
        client.setEnvironmentName("[custom_env_name]")
        client.notify(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.context.environment).to.equal("[custom_env_name]")

      it "reports environment", ->
        client.addEnvironment(env_key: "[custom_env]")
        client.notify(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.environment.env_key).to.equal("[custom_env]")

      it "reports params", ->
        client.addParams(params_key: "[custom_params]")
        client.notify(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.params.params_key).to.equal("[custom_params]")

      it "reports session", ->
        client.addSession(session_key: "[custom_session]")
        client.notify(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.session.session_key).to.equal("[custom_session]")

      describe "wrapped error", ->
        it "unwraps and processes error", ->
          client.notify(error: exception)
          expect(processor).to.have.been.calledWith(exception)

        it "reports custom context", ->
          client.addContext(context1: "value1", context2: "value2")
          client.notify
            error: exception
            context:
              context1: "notify_value1"
              context3: "notify_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.context).to.deep.equal
            language: "JavaScript"
            sourceMapEnabled: true
            context1: "notify_value1"
            context2: "value2"
            context3: "notify_value3"

        it "reports custom environment name", ->
          client.setEnvironmentName("env1")
          client.notify
            error: exception
            context:
              environment: "notify_env1"

          reported = reporter.lastCall.args[0]
          expect(reported.context).to.deep.equal
            language: "JavaScript"
            sourceMapEnabled: true
            environment: "notify_env1"

        it "reports custom environment", ->
          client.addEnvironment(env1: "value1", env2: "value2")
          client.notify
            error: exception
            environment:
              env1: "notify_value1"
              env3: "notify_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.environment).to.deep.equal
            env1: "notify_value1"
            env2: "value2"
            env3: "notify_value3"

        it "reports custom params", ->
          client.addParams(param1: "value1", param2: "value2")
          client.notify
            error: exception
            params:
              param1: "notify_value1"
              param3: "notify_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.params).to.deep.equal
            param1: "notify_value1"
            param2: "value2"
            param3: "notify_value3"

        it "reports custom session", ->
          client.addSession(session1: "value1", session2: "value2")
          client.notify
            error: exception
            session:
              session1: "notify_value1"
              session3: "notify_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.session).to.deep.equal
            session1: "notify_value1"
            session2: "value2"
            session3: "notify_value3"

    describe 'with location', ->
      notice = null

      beforeEach ->
        global.location = {
          protocol: 'http:',
          host: 'subdomain.domain.com',
          toString: -> 'http://subdomain.domain.com/path',
        }
        client.notify(exception)
        expect(reporter).to.have.been.called
        notice = reporter.lastCall.args[0]

      it 'reports context.url', ->
        expect(notice.context.url).to.equal('http://subdomain.domain.com/path')

      it 'reports context.rootDirectory', ->
        expect(notice.context.rootDirectory).to.equal('http://subdomain.domain.com')

  describe "custom reporter", ->
    it "is called on error", ->
      custom_reporter = sinon.spy()
      client.addReporter(custom_reporter)
      client.notify(error: {})
      expect(custom_reporter).to.have.been.called

  testWrap(new Client(processor: null, reporter: null))
